"""Offline regression tests using synthetic messages only."""

from contextlib import redirect_stdout
from datetime import timedelta
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import uuid
import zipfile

import wechat_archive as subject


TRANSCRIPT = (
    "·测试甲\n2026年10月29日 09:01\n第一条\n第二行\n"
    "·测试乙\n2026年10月29日 09:02\n重复消息\n"
    "·测试乙\n2026年10月29日 09:02\n重复消息\n"
)
CLIPBOARD_TRANSCRIPT = (
    "测试甲\n2026年10月29日 09:01\n第一条\n第二行\n\n"
    "测试乙\n2026年10月29日 09:02\n重复消息\n\n"
    "测试乙\n2026年10月29日 09:02\n重复消息"
)


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="wechat-skill-test-")
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def make_zip(self, files=None, name="export.zip"):
        path = self.root / name
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for member, content in (files or {"聊天记录.txt": TRANSCRIPT}).items():
                archive.writestr(member, content)
        return path

    def invoke(self, *args):
        output = io.StringIO()
        with redirect_stdout(output):
            code = subject.main(list(args))
        return code, json.loads(output.getvalue())

    def test_bom_crlf_multiline_and_duplicates(self):
        records = subject.parse_transcript("\ufeff" + TRANSCRIPT.replace("\n", "\r\n"))
        self.assertEqual(len(records), 3)
        self.assertEqual(records[0]["text"], "第一条\n第二行")
        self.assertEqual(records[1]["text"], records[2]["text"])
        self.assertNotEqual(records[1]["index"], records[2]["index"])

    def test_clipboard_matches_native_records_without_bridge(self):
        path = self.root / "clipboard.txt"
        original = ("\ufeff" + CLIPBOARD_TRANSCRIPT.replace("\n", "\r\n")).encode("utf-8")
        path.write_bytes(original)
        with patch.object(subject, "default_inbox", side_effect=AssertionError("Bridge must not be consulted")):
            code, result = self.invoke("inspect-text", "--text-path", str(path), "--records", "--expect-count", "3")
        self.assertEqual(code, 0)
        self.assertEqual(result["records"], subject.parse_transcript(TRANSCRIPT))
        self.assertTrue(result["countMatches"])
        self.assertFalse(result["attachmentsVerified"])
        self.assertEqual(path.read_bytes(), original)

    def test_clipboard_sender_symbols_and_body_paragraphs_are_retained(self):
        body = "·测试甲\n2026年10月29日 09:01\n第一段\n\n第二段\n2026年10月29日 09:02\n仍是正文"
        records = subject.parse_transcript(body, "clipboard")
        self.assertEqual(len(records), 2)
        # Text has no escaping: a header-looking quote is inherently ambiguous.
        # A caller's expected UI count catches this case instead of hiding it.
        path = self.root / "quoted.txt"
        path.write_text(body, encoding="utf-8")
        code, result = self.invoke("inspect-text", "--text-path", str(path), "--expect-count", "1")
        self.assertEqual(code, 2)
        self.assertFalse(result["countMatches"])
        self.assertEqual(records[0]["sender"], "·测试甲")
        ordinary = body.replace("2026年10月29日 09:02", "不是消息时间")
        single = subject.parse_transcript(ordinary, "clipboard")
        self.assertEqual(len(single), 1)
        self.assertIn("第一段\n\n第二段", single[0]["text"])

    def test_clipboard_invalid_or_incomplete_header_fails(self):
        path = self.root / "invalid.txt"
        for body in ("unrelated clipboard text", "甲\n2026年99月29日 09:01\n正文", "甲\n2026年10月29日 09:01"):
            path.write_text(body, encoding="utf-8")
            code, result = self.invoke("inspect-text", "--text-path", str(path))
            self.assertEqual(code, 2)
            self.assertIsNone(result["messageCount"])
        path.write_bytes(b"\xff\xfe\x00")
        self.assertEqual(subject.inspect_text_file(path)["reason"], "unsupported_text_encoding")

    def test_clipboard_report_does_not_expose_bodies_by_default(self):
        path = self.root / "clipboard.txt"
        path.write_text(CLIPBOARD_TRANSCRIPT, encoding="utf-8")
        result = subject.inspect_text_file(path)
        self.assertNotIn("records", result)
        self.assertNotIn("重复消息", json.dumps(result, ensure_ascii=False))
        with patch.object(subject, "MAX_TEXT", 5):
            with self.assertRaisesRegex(ValueError, "Transcript exceeds"):
                subject.inspect_text_file(path)

    def test_metadata_does_not_include_message_bodies(self):
        path = self.make_zip({"nested/聊天记录.txt": TRANSCRIPT, "images/photo.png": b"synthetic"})
        result = subject.inspect_archive(path, expect_count=3)
        self.assertEqual(result["messageCount"], 3)
        self.assertTrue(result["countMatches"])
        self.assertNotIn("records", result)
        self.assertNotIn("第一条", json.dumps(result, ensure_ascii=False))
        self.assertEqual(result["attachments"][0]["member"], "images/photo.png")
        self.assertEqual(result["sha256"], subject.sha256_file(path))

    def test_count_mismatch_returns_nonzero_and_actual_count(self):
        code, result = self.invoke("inspect", "--zip", str(self.make_zip()), "--expect-count", "20")
        self.assertEqual(code, 2)
        self.assertEqual(result["messageCount"], 3)
        self.assertFalse(result["countMatches"])

    def test_unknown_format_and_encoding_are_not_zero_messages(self):
        for name, text in [("unknown.zip", "Some other transcript format"), ("encoding.zip", b"\xff\xfe\x00")]:
            path = self.make_zip({"聊天记录.txt": text}, name)
            code, result = self.invoke("inspect", "--zip", str(path))
            self.assertEqual(code, 2)
            self.assertIsNone(result["messageCount"])
            self.assertEqual(result["format"], "unrecognized")
        self.assertIsNone(subject.parse_transcript(TRANSCRIPT.replace("10月", "99月")))

    def test_multiple_native_transcripts_require_explicit_member(self):
        path = self.make_zip({"a/聊天记录.txt": TRANSCRIPT, "b/聊天记录.txt": TRANSCRIPT})
        with self.assertRaisesRegex(ValueError, "Multiple candidate"):
            subject.inspect_archive(path)
        self.assertEqual(subject.inspect_archive(path, member="a/聊天记录.txt")["messageCount"], 3)

    def test_path_traversal_rejected_without_extracting(self):
        path = self.make_zip({"../escape.txt": "bad", "聊天记录.txt": TRANSCRIPT})
        with self.assertRaisesRegex(ValueError, "Unsafe relative"):
            subject.inspect_archive(path)
        self.assertFalse((self.root.parent / "escape.txt").exists())

    def test_invalid_crc_rejected(self):
        path = self.root / "corrupt.zip"
        body = TRANSCRIPT.encode("utf-8")
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as archive:
            archive.writestr("聊天记录.txt", body)
        data = path.read_bytes()
        offset = data.index(body)
        path.write_bytes(data[:offset] + bytes([data[offset] ^ 1]) + data[offset + 1:])
        code, result = self.invoke("inspect", "--zip", str(path))
        self.assertEqual(code, 2)
        self.assertIn("CRC", result["error"])

    def test_output_is_utf8_and_cannot_overwrite(self):
        path = self.make_zip()
        target = self.root / "results" / "messages.json"
        code, result = self.invoke("inspect", "--zip", str(path), "--records", "--output", str(target))
        self.assertEqual(code, 0)
        saved = json.loads(target.read_text(encoding="utf-8"))
        self.assertEqual(saved["records"][0]["sender"], "测试甲")
        original = target.read_bytes()
        code, _ = self.invoke("inspect", "--zip", str(path), "--output", str(target))
        self.assertEqual(code, 2)
        self.assertEqual(target.read_bytes(), original)

    def add_batch(self, inbox, relative="files/聊天记录.zip", declared_size=3):
        batch = inbox / "Ready" / str(uuid.uuid4())
        (batch / "files").mkdir(parents=True)
        (batch / "files" / "聊天记录.zip").write_bytes(b"zip")
        subject.write_new_json(batch / "manifest.json", {
            "schemaVersion": 1, "batchId": batch.name, "createdAt": subject.stamp(),
            "action": "clipboard", "items": [{"relativePath": relative, "byteCount": declared_size}],
        })
        return batch

    def test_only_new_batches_and_no_historical_manifest_read(self):
        inbox = self.root / "Inbox"
        old = self.add_batch(inbox)
        (old / "manifest.json").write_text("not even valid JSON", encoding="utf-8")
        baseline = self.root / "before.json"
        subject.write_new_json(baseline, subject.snapshot(inbox))
        new = self.add_batch(inbox)
        result = subject.changes(baseline)
        self.assertEqual([b["batchId"] for b in result["newBatches"]], [new.name])
        self.assertEqual(result["rejectedBatches"], [])

    def test_missing_inbox_can_appear_after_snapshot(self):
        inbox = self.root / "Inbox"
        baseline = self.root / "before.json"
        subject.write_new_json(baseline, subject.snapshot(inbox))
        self.assertFalse(inbox.exists())
        self.add_batch(inbox)
        self.assertEqual(len(subject.changes(baseline)["newBatches"]), 1)

    def test_bad_manifest_path_and_size_are_rejected(self):
        inbox = self.root / "Inbox"
        baseline = self.root / "before.json"
        subject.write_new_json(baseline, subject.snapshot(inbox))
        self.add_batch(inbox, relative="../../outside.zip")
        self.add_batch(inbox, declared_size=999)
        result = subject.changes(baseline)
        self.assertEqual(len(result["rejectedBatches"]), 2)
        self.assertEqual(result["newBatches"], [])

    def test_stale_baseline_is_rejected(self):
        baseline = subject.snapshot(self.root / "Inbox")
        baseline["capturedAt"] = (subject.utc_now() - timedelta(hours=1)).isoformat()
        path = self.root / "before.json"
        subject.write_new_json(path, baseline)
        with self.assertRaisesRegex(ValueError, "stale"):
            subject.changes(path)


if __name__ == "__main__":
    unittest.main(verbosity=2)
