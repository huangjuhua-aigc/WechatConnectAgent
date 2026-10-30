import json
from pathlib import Path
import tempfile
import unittest
import zipfile
import plistlib
from importlib.util import spec_from_file_location, module_from_spec

spec = spec_from_file_location("package_release", Path(__file__).with_name("package-release.py"))
package = module_from_spec(spec)
spec.loader.exec_module(package)


class ReleaseTests(unittest.TestCase):
    def fixture(self, base):
        root, build = base / "repo", base / "private-build"
        for folder in (root / "skills/wechat-chat-select", root / "docs", root / "scripts", build / "Assets", build / "private"):
            folder.mkdir(parents=True)
        (root / "skills/wechat-chat-select/SKILL.md").write_text("synthetic skill", encoding="utf-8")
        for name in ("README.md", "LICENSE", "scripts/install-windows.ps1"):
            (root / name).write_text("synthetic fixture", encoding="utf-8")
        for name in package.BUILD_NAMES:
            (build / name).write_bytes(b"synthetic binary")
        for name in ("Logo44.png", "Logo150.png"):
            (build / "Assets" / name).write_bytes(b"synthetic icon")
        (build / "private/signing.pfx").write_bytes(b"PRIVATE TEST FIXTURE")
        info = dict(version="0.1.8", packageVersion="0.1.8.0", packaging="msix", thumbprint="synthetic",
                    build="C:/private/username", executableSha256=package.sha256(b"synthetic binary"),
                    packageSha256=package.sha256(b"synthetic binary"))
        (build / "build-info.json").write_text(json.dumps(info), encoding="utf-8")
        return root, build

    def test_portable_payload_hashes_and_private_key_exclusion(self):
        with tempfile.TemporaryDirectory() as temporary:
            root, build = self.fixture(Path(temporary))
            version, payload = package.collect_payload(root, build)
            self.assertEqual(version, "0.1.8")
            self.assertFalse(any("private" in name or name.endswith(".pfx") for name in payload))
            self.assertNotIn(b"C:/private/username", payload["receiver-windows/build-info.json"])
            for name, digest in json.loads(payload["files.sha256.json"]).items():
                self.assertEqual(package.sha256(payload[name]), digest)
            destination = Path(temporary) / "bundle.zip"
            package.write_archive(destination, payload)
            with zipfile.ZipFile(destination) as zipped:
                self.assertIsNone(zipped.testzip())
                self.assertEqual(set(zipped.namelist()), set(payload))

    def test_changed_build_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root, build = self.fixture(Path(temporary))
            (build / "AgentChatReceiver.exe").write_bytes(b"modified")
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                package.collect_payload(root, build)

    def test_unexpected_private_file_in_skill_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root, build = self.fixture(Path(temporary))
            (root / "skills/wechat-chat-select/accidental.pfx").write_bytes(b"private fixture")
            with self.assertRaisesRegex(ValueError, "Unexpected source"):
                package.collect_payload(root, build)

    def test_mac_package_preserves_executable_modes_and_integrity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root, _ = self.fixture(Path(temporary))
            app = Path(temporary) / "ChatInbox.app"
            (app / "Contents/MacOS").mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "com.wechatconnectagent.receiver", "CFBundleShortVersionString": "0.2.0"}))
            (app / "Contents/MacOS/ChatInbox").write_bytes(b"synthetic executable")
            version, payload = package.collect_macos(root, app)
            self.assertEqual(version, "0.2.0")
            self.assertEqual(json.loads(payload["bundle.json"])["platform"], "macos-universal")
            for name, digest in json.loads(payload["files.sha256.json"]).items():
                self.assertEqual(package.sha256(payload[name]), digest)
            destination = Path(temporary) / "mac.zip"
            package.write_archive(destination, payload)
            with zipfile.ZipFile(destination) as archive:
                entry = archive.getinfo("receiver-macos/ChatInbox.app/Contents/MacOS/ChatInbox")
                self.assertEqual((entry.external_attr >> 16) & 0o777, 0o755)


if __name__ == "__main__":
    unittest.main()
