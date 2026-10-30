"""Inspect explicitly selected WeChat exports; never control WeChat or use the network."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import uuid
import zipfile


MAX_ARCHIVE = 1024 * 1024 * 1024
MAX_TEXT = 16 * 1024 * 1024
MAX_JSON = 1024 * 1024
MAX_ENTRIES = 1000
HEADER = re.compile(
    r"(?m)^·([^\n]+)\n(\d{4})年(\d{1,2})月(\d{1,2})日 (\d{2}):(\d{2})\n"
)
CLIPBOARD_HEADER = re.compile(
    r"(?:\A|(?<=\n\n))([^\n]+)\n(\d{4})年(\d{1,2})月(\d{1,2})日 (\d{2}):(\d{2})\n"
)


def utc_now():
    return datetime.now(timezone.utc)


def stamp():
    return utc_now().isoformat()


def default_inbox():
    local = os.environ.get("LOCALAPPDATA")
    if not local:
        raise ValueError("LOCALAPPDATA is unavailable; supply --inbox explicitly.")
    return Path(local) / "WeChatBridge" / "Inbox"


def read_json(path):
    path = Path(path)
    with path.open("rb") as handle:
        data = handle.read(MAX_JSON + 1)
    if len(data) > MAX_JSON:
        raise ValueError("JSON exceeds the 1 MiB limit.")
    return json.loads(data.decode("utf-8-sig"))


def write_new_json(path, payload):
    path = Path(path).resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    return str(path)


def safe_relative(value):
    if not isinstance(value, str) or not value or "\x00" in value:
        raise ValueError("Missing or invalid relative path.")
    normalized = value.replace("\\", "/")
    pieces = normalized.split("/")
    if normalized.startswith("/") or any(p in (".", "..") or ":" in p for p in pieces):
        raise ValueError("Unsafe relative path in archive or manifest.")
    return PurePosixPath(normalized)


def contained_file(directory, relative):
    root = Path(directory).resolve()
    candidate = (root / str(safe_relative(relative))).resolve()
    if not candidate.is_relative_to(root) or not candidate.is_file():
        raise ValueError("Manifest file is missing or leaves its batch directory.")
    return candidate


def ready_directories(root):
    root = Path(root).resolve()
    ready = root / "Ready"
    if not ready.exists():
        return []
    if not ready.resolve().is_relative_to(root):
        raise ValueError("Ready directory leaves the requested inbox.")
    batches = []
    for path in ready.iterdir():
        if not path.is_dir():
            continue
        try:
            uuid.UUID(path.name)
        except ValueError:
            continue
        if not path.resolve().is_relative_to(ready.resolve()):
            raise ValueError("Batch directory leaves Ready.")
        batches.append(path)
    return sorted(batches, key=lambda p: p.name)


def snapshot(root):
    root = Path(root).resolve()
    return {
        "schemaVersion": 1,
        "capturedAt": stamp(),
        "inbox": str(root),
        "inboxExists": root.is_dir(),
        # Names only: do not read historical manifests or chat bodies.
        "batchIds": [str(uuid.UUID(p.name)) for p in ready_directories(root)],
    }


def parse_utc(value):
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("Expected a timestamp with a timezone.")
    return parsed.astimezone(timezone.utc)


def changes(baseline_path, max_age=1800):
    baseline = read_json(baseline_path)
    if baseline.get("schemaVersion") != 1 or not isinstance(baseline.get("batchIds"), list):
        raise ValueError("Invalid inbox snapshot.")
    captured = parse_utc(baseline["capturedAt"])
    age = (utc_now() - captured).total_seconds()
    if age < -5 or age > max_age:
        raise ValueError("Snapshot is stale or in the future; create a fresh baseline.")
    root = Path(baseline["inbox"]).resolve()
    known = set(baseline["batchIds"])
    found, rejected = [], []
    for directory in ready_directories(root):
        batch_id = str(uuid.UUID(directory.name))
        if batch_id in known:
            continue
        try:
            manifest_path = contained_file(directory, "manifest.json")
            manifest = read_json(manifest_path)
            if manifest.get("schemaVersion") != 1:
                raise ValueError("Unsupported manifest schema.")
            if str(uuid.UUID(manifest["batchId"])) != batch_id:
                raise ValueError("Manifest ID does not match its batch directory.")
            created = parse_utc(manifest["createdAt"])
            if (created - captured).total_seconds() < -2 or (created - utc_now()).total_seconds() > 5:
                raise ValueError("Batch creation time is outside this capture window.")
            items = manifest.get("items")
            if not isinstance(items, list) or not 1 <= len(items) <= MAX_ENTRIES:
                raise ValueError("Invalid item list.")
            files = []
            for item in items:
                path = contained_file(directory, item["relativePath"])
                size = path.stat().st_size
                if not isinstance(item.get("byteCount"), int) or size != item["byteCount"]:
                    raise ValueError("File size does not match manifest.")
                if size > MAX_ARCHIVE:
                    raise ValueError("File exceeds the 1 GiB limit.")
                files.append({"path": str(path), "bytes": size, "isZip": path.suffix.lower() == ".zip"})
            found.append({
                "batchId": batch_id, "createdAt": manifest["createdAt"],
                "action": manifest.get("action"), "manifest": str(manifest_path), "files": files,
            })
        except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
            rejected.append({"batchId": batch_id, "error": str(error)})
    return {
        "inbox": str(root), "capturedAt": baseline["capturedAt"], "checkedAt": stamp(),
        "newBatches": found, "rejectedBatches": rejected,
        "chatIdentityVerified": False,
    }


def parse_transcript(text, transcript_format="native"):
    text = text.lstrip("\ufeff").replace("\r\n", "\n")
    if transcript_format not in ("native", "clipboard"):
        raise ValueError("Unsupported transcript format.")
    header = HEADER if transcript_format == "native" else CLIPBOARD_HEADER
    matches = list(header.finditer(text))
    if not matches or matches[0].start() != 0:
        return None
    records = []
    try:
        for index, match in enumerate(matches):
            when = datetime(*(int(match.group(i)) for i in range(2, 7)))
            end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
            records.append({
                "index": index + 1, "sender": match.group(1),
                "time": when.isoformat(timespec="minutes"),
                "text": text[match.end():end].strip(),
            })
    except ValueError:
        return None
    return records


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inspect_text_file(path, transcript_format="clipboard", include_records=False, expect_count=None):
    path = Path(path).resolve(strict=True)
    with path.open("rb") as handle:
        data = handle.read(MAX_TEXT + 1)
    if len(data) > MAX_TEXT:
        raise ValueError("Transcript exceeds the 16 MiB limit.")
    records = None
    try:
        records = parse_transcript(data.decode("utf-8-sig"), transcript_format)
        reason = None if records is not None else "unknown_transcript_format"
    except UnicodeDecodeError:
        reason = "unsupported_text_encoding"
    count = len(records) if records is not None else None
    result = {
        "textFile": str(path), "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
        "format": ("wechat_clipboard_text" if transcript_format == "clipboard" else "wechat_native_txt")
                  if records is not None else "unrecognized",
        "reason": reason, "messageCount": count,
        "timezone": "local_unspecified", "timePrecision": "minute",
        "expectedCount": expect_count,
        "countMatches": count == expect_count if expect_count is not None else None,
        "first": {k: v for k, v in records[0].items() if k != "text"} if records else None,
        "last": {k: v for k, v in records[-1].items() if k != "text"} if records else None,
        "timeMin": min(r["time"] for r in records) if records else None,
        "timeMax": max(r["time"] for r in records) if records else None,
        "attachmentsVerified": False, "selectionVerified": False,
    }
    if include_records:
        result["records"] = records
    return result


def inspect_archive(path, member=None, include_records=False, expect_count=None):
    path = Path(path).resolve(strict=True)
    if path.stat().st_size > MAX_ARCHIVE:
        raise ValueError("Archive exceeds the 1 GiB limit.")
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        if not 1 <= len(infos) <= MAX_ENTRIES:
            raise ValueError("ZIP entry count outside supported bounds.")
        total, seen = 0, set()
        texts = []
        for info in infos:
            safe_relative(info.filename)
            if info.filename in seen:
                raise ValueError("Duplicate ZIP member name.")
            seen.add(info.filename)
            if stat.S_ISLNK(info.external_attr >> 16):
                raise ValueError("ZIP symlinks are unsupported.")
            if info.flag_bits & 1 or info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                raise ValueError("Encrypted or unsupported ZIP compression.")
            total += info.file_size
            if total > MAX_ARCHIVE:
                raise ValueError("Expanded archive exceeds the 1 GiB limit.")
            if not info.is_dir() and info.filename.lower().endswith(".txt"):
                texts.append(info)
        selected = None
        if member is not None:
            selected = next((i for i in texts if i.filename == member), None)
            if selected is None:
                raise ValueError("Requested TXT member is not present.")
        elif texts:
            native = [i for i in texts if PurePosixPath(i.filename.replace("\\", "/")).name == "聊天记录.txt"]
            choices = native or texts
            if len(choices) != 1:
                raise ValueError("Multiple candidate TXT files; inspect member names and supply --member: " +
                                 json.dumps([i.filename for i in choices], ensure_ascii=False))
            selected = choices[0]
        records, reason = None, "no_txt_member"
        if selected is not None:
            if selected.file_size > MAX_TEXT:
                raise ValueError("Transcript exceeds the 16 MiB limit.")
            with archive.open(selected) as handle:
                data = handle.read(MAX_TEXT + 1)
            if len(data) > MAX_TEXT:
                raise ValueError("Transcript exceeds the 16 MiB limit.")
            try:
                records = parse_transcript(data.decode("utf-8-sig"))
                reason = None if records is not None else "unknown_transcript_format"
            except UnicodeDecodeError:
                reason = "unsupported_text_encoding"
        count = len(records) if records is not None else None
        result = {
            "archive": str(path), "sha256": sha256_file(path), "bytes": path.stat().st_size,
            "format": "wechat_native_txt" if records is not None else "unrecognized",
            "reason": reason, "transcriptMember": selected.filename if selected else None,
            "messageCount": count, "timezone": "local_unspecified", "timePrecision": "minute",
            "expectedCount": expect_count,
            "countMatches": count == expect_count if expect_count is not None else None,
            "first": {k: v for k, v in records[0].items() if k != "text"} if records else None,
            "last": {k: v for k, v in records[-1].items() if k != "text"} if records else None,
            "timeMin": min(r["time"] for r in records) if records else None,
            "timeMax": max(r["time"] for r in records) if records else None,
            "attachments": [{"member": i.filename, "bytes": i.file_size} for i in infos
                            if not i.is_dir() and i is not selected],
            "crcScope": "selected_txt_only" if selected is not None else "none",
            "selectionVerified": False,
        }
        if include_records:
            result["records"] = records
        return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    doctor = commands.add_parser("doctor", help="Check platform and inbox, without reading chat content.")
    doctor.add_argument("--inbox")
    capture = commands.add_parser("snapshot", help="Record existing batch IDs before sharing.")
    capture.add_argument("--inbox")
    capture.add_argument("--output", required=True)
    diff = commands.add_parser("changes", help="List newly committed batches only.")
    diff.add_argument("--baseline", required=True)
    diff.add_argument("--max-age-seconds", type=int, default=1800)
    inspect = commands.add_parser("inspect", help="Read one explicitly selected ZIP.")
    inspect.add_argument("--zip", required=True)
    inspect.add_argument("--member")
    inspect.add_argument("--records", action="store_true")
    inspect.add_argument("--expect-count", type=int)
    inspect.add_argument("--output")
    text_inspect = commands.add_parser("inspect-text", help="Read a saved native clipboard transcript; no Bridge required.")
    text_inspect.add_argument("--text-path", required=True)
    text_inspect.add_argument("--text-format", choices=("clipboard", "native"), default="clipboard")
    text_inspect.add_argument("--records", action="store_true")
    text_inspect.add_argument("--expect-count", type=int)
    text_inspect.add_argument("--output")
    args = parser.parse_args(argv)
    exit_code = 0
    try:
        if args.command == "doctor":
            root = Path(args.inbox).resolve() if args.inbox else default_inbox()
            result = {"platform": sys.platform, "python": sys.version.split()[0], "inbox": str(root),
                      "inboxExists": root.is_dir(), "readyExists": (root / "Ready").is_dir(),
                      "desktopAutomationTested": False, "bridgeInstallationVerified": False}
        elif args.command == "snapshot":
            result = snapshot(args.inbox or default_inbox())
            output = write_new_json(args.output, result)
            result = {"snapshot": output, "inbox": result["inbox"], "inboxExists": result["inboxExists"],
                      "existingBatchCount": len(result["batchIds"]), "capturedAt": result["capturedAt"]}
        elif args.command == "changes":
            if args.max_age_seconds <= 0:
                raise ValueError("max-age-seconds must be positive.")
            result = changes(args.baseline, args.max_age_seconds)
            exit_code = 2 if result["rejectedBatches"] else 0
        else:
            if args.expect_count is not None and args.expect_count < 0:
                raise ValueError("expect-count must be nonnegative.")
            if args.command == "inspect-text":
                result = inspect_text_file(args.text_path, args.text_format, args.records, args.expect_count)
            else:
                result = inspect_archive(args.zip, args.member, args.records, args.expect_count)
            exit_code = 2 if result["format"] == "unrecognized" or result["countMatches"] is False else 0
            if args.output:
                output = write_new_json(args.output, result)
                result = {"output": output, "format": result["format"], "messageCount": result["messageCount"],
                          "countMatches": result["countMatches"], "sha256": result["sha256"]}
    except (OSError, ValueError, KeyError, TypeError, AttributeError, zipfile.BadZipFile, RuntimeError) as error:
        result = {"error": str(error), "command": args.command}
        exit_code = 2
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return exit_code


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
