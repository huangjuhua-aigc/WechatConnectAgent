"""Create a portable release from allowed inputs; never include signing keys or chats."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE_SUFFIXES = {".md", ".py", ".ps1", ".cs", ".xml", ".yaml", ".txt", ".manifest"}
BUILD_NAMES = (
    "AgentChatReceiver.exe", "AgentChatReceiver.exe.config", "AgentChatReceiver.msix",
    "AgentChatReceiver.cer", "resources.pri", "THIRD_PARTY_NOTICES.txt",
)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def collect_payload(root, build):
    info = json.loads((build / "build-info.json").read_text(encoding="utf-8-sig"))
    version = info["version"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or info["packageVersion"] != version + ".0":
        raise ValueError("Unexpected release version")
    for name, key in (("AgentChatReceiver.exe", "executableSha256"), ("AgentChatReceiver.msix", "packageSha256")):
        if sha256((build / name).read_bytes()).lower() != info[key].lower():
            raise ValueError("Build hash mismatch: " + name)
    portable = {key: info[key] for key in ("version", "packageVersion", "packaging", "thumbprint", "packageSha256", "executableSha256")}
    portable.update(package="AgentChatReceiver.msix", certificate="AgentChatReceiver.cer")
    payload = {}
    for folder in ("skills/wechat-chat-select", "docs"):
        for path in sorted((root / folder).rglob("*")):
            if not path.is_file() or "__pycache__" in path.parts:
                continue
            relative = path.relative_to(root)
            if path.is_symlink() or any(part in {"private", "build", "Inbox", ".git"} for part in relative.parts):
                raise ValueError("Unexpected private or linked source: " + str(relative))
            if path.suffix not in SOURCE_SUFFIXES and path.name != '.gitignore':
                raise ValueError("Unexpected source file: " + str(relative))
            payload[relative.as_posix()] = path.read_bytes()
    for name in ("README.md", "LICENSE"):
        payload[name] = (root / name).read_bytes()
    payload["setup.ps1"] = (root / "scripts/install-windows.ps1").read_bytes()
    for name in BUILD_NAMES:
        payload["receiver-windows/" + name] = (build / name).read_bytes()
    for name in ("Logo44.png", "Logo150.png"):
        payload["receiver-windows/Assets/" + name] = (build / "Assets" / name).read_bytes()
    payload["receiver-windows/build-info.json"] = json_bytes(portable)
    payload["bundle.json"] = json_bytes({"version": version, "platform": "windows-x64"})
    payload["files.sha256.json"] = json_bytes({name: sha256(data) for name, data in sorted(payload.items())})
    return version, payload


def write_archive(path, payload):
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(payload.items()):
            entry = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, data)
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError("Archive CRC failure")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    version, payload = collect_payload(ROOT, args.build.resolve())
    args.output.mkdir(parents=True, exist_ok=True)
    asset = "WechatConnectAgent-windows-x64-" + version + ".zip"
    destination = args.output / asset
    write_archive(destination, payload)
    digest = sha256(destination.read_bytes())
    (args.output / "SHA256SUMS.txt").write_text(digest + "  " + asset + "\n", encoding="ascii")
    manifest = {
        "version": version, "platform": "windows-x64", "asset": asset, "sha256": digest,
        "url": "https://github.com/huangjuhua-aigc/WechatConnectAgent/releases/download/v" + version + "/" + asset,
        "signingCertificateThumbprint": json.loads(payload["receiver-windows/build-info.json"])["thumbprint"],
        "macosSupported": False,
    }
    (args.output / "release.json").write_bytes(json_bytes(manifest))
    bootstrap = ROOT / "install.ps1"
    source = bootstrap.read_text(encoding="utf-8")
    source, count = re.subn(r"(?m)^\$archiveSha256 = '[^']*'$", "$archiveSha256 = '" + digest + "'", source)
    if count != 1 or ("$releaseVersion = '" + version + "'") not in source:
        raise ValueError("Bootstrap version/hash field missing or inconsistent")
    bootstrap.write_text(source, encoding="utf-8")
    (args.output / "install.ps1").write_bytes(bootstrap.read_bytes())
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
