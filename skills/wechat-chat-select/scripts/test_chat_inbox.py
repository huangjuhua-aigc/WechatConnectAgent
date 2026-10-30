"""Synthetic receiver and portable-reader tests. No real chat data or model calls."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

import chat_inbox
import wechat_archive


RECEIVER = os.environ.get("CHAT_RECEIVER_EXE")
TEXT = "·Example\n2026年10月30日 00:01\nSynthetic message\n"


@unittest.skipUnless(RECEIVER, "Set CHAT_RECEIVER_EXE to test the compiled native receiver")
class ReceiverTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="chat-receiver-test-")
        self.root = Path(self.temp.name)
        self.inbox = self.root / "inbox"

    def tearDown(self):
        self.temp.cleanup()

    def capture(self, payload, max_bytes=None):
        fixture = self.root / "input.json"
        fixture.write_text(json.dumps(payload), encoding="utf-8")
        receipt = self.root / "receipt.json"
        args = [RECEIVER, "--import", str(fixture), "--inbox", str(self.inbox), "--result", str(receipt)]
        if max_bytes:
            args += ["--max-bytes", str(max_bytes)]
        process = subprocess.run(args, timeout=15, capture_output=True,
                                 creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        result = json.loads(receipt.read_text(encoding="utf-8"))
        return process.returncode, result

    def test_multi_format_receipt_and_export_preserves_originals(self):
        zipped = self.root / "chat.zip"
        media = b"synthetic-media-bytes\x00\xff"
        with zipfile.ZipFile(zipped, "w", compression=zipfile.ZIP_DEFLATED) as handle:
            handle.writestr("聊天记录.txt", TEXT)
            handle.writestr("images/test.png", media)
            handle.writestr("videos/test.mp4", media)
            handle.writestr("documents/test.unknown", media)
        unknown = self.root / "standalone.unknown"
        unknown.write_bytes(media)
        code, receipt = self.capture({"files": [str(zipped), str(unknown)], "text": "ordinary text",
                                      "uri": "https://example.com", "html": "<script>untrusted</script>", "rtf": r"{\rtf1 example}"})
        self.assertEqual(code, 0, receipt)
        manifest = json.loads(Path(receipt["manifest"]).read_text(encoding="utf-8"))
        self.assertEqual(len(manifest["items"]), 6)
        exported = chat_inbox.export_batch(receipt["manifest"], self.root / "export")
        self.assertEqual(exported["parsedMessageCount"], 1)
        self.assertFalse(exported["interpretationIncomplete"])
        self.assertEqual(len(exported["files"][0]["extracted"]), 4)
        self.assertEqual(Path(exported["files"][1]["path"]).read_bytes(), media)
        self.assertEqual(exported["transcripts"][0]["records"][0]["text"], "Synthetic message")
        self.assertFalse(list((self.inbox / "Staging").iterdir()))

    def test_limit_failure_never_commits_ready(self):
        code, receipt = self.capture({"text": "x" * 20}, max_bytes=10)
        self.assertEqual(code, 2)
        self.assertFalse(receipt["ok"])
        self.assertFalse((self.inbox / "Ready").exists())
        self.assertEqual(len(list((self.inbox / "Failed").iterdir())), 1)

    def test_same_filename_is_preserved_twice(self):
        paths = []
        for name, content in (("a", b"first"), ("b", b"second")):
            folder = self.root / name
            folder.mkdir()
            file = folder / "same.dat"
            file.write_bytes(content)
            paths.append(str(file))
        code, receipt = self.capture({"files": paths})
        self.assertEqual(code, 0, receipt)
        result = chat_inbox.export_batch(receipt["manifest"], self.root / "export")
        self.assertEqual([Path(i["path"]).read_bytes() for i in result["files"]], [b"first", b"second"])

    def test_corrupted_manifest_fails_before_export(self):
        code, receipt = self.capture({"text": TEXT})
        self.assertEqual(code, 0)
        manifest_path = Path(receipt["manifest"])
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        received = manifest_path.parent / manifest["items"][0]["relativePath"]
        received.write_bytes(received.read_bytes().replace(b"Example", b"Changed"))
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            chat_inbox.export_batch(manifest_path, self.root / "export")
        self.assertFalse((self.root / "export").exists())


class ZipTests(unittest.TestCase):
    def test_unsafe_members_fail_before_extraction(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for names in (("../escape.txt",), ("CON.txt",), ("Case.txt", "case.txt"), ("a", "a/b")):
                zipped = root / "bad.zip"
                with zipfile.ZipFile(zipped, "w") as handle:
                    for name in names:
                        handle.writestr(name, "test")
                with self.assertRaises(ValueError):
                    chat_inbox.extract_zip(zipped, root / "unpack")
                self.assertFalse((root / "unpack").exists())


if __name__ == "__main__":
    unittest.main()
