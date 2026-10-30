# Development and releases

Windows: C#/.NET 4.8, SDK 19041+. Mac: Swift 5.9+, macOS 13+, AppKit/Foundation. Readers: Python 3.9+ standard library. Bootstrap: Node.js 20+, zero npm dependencies or lifecycle scripts.

## Build and test

```powershell
pwsh -NoProfile -File skills/wechat-chat-select/receiver/build.ps1 -OutputDirectory <private-build-directory> -Sign
python scripts/package-release.py --build <private-build-directory> --output dist
```

Reuse the authorized signing key. Keep private build files outside the repo; never publish PFX, private metadata or chats. A new certificate requires a deliberate installer update and new user trust.

On a Mac:

```sh
swift test --package-path macos
bash macos/build.sh "$PWD/dist/macos-build"
python scripts/package-release.py --macos-app dist/macos-build/ChatInbox.app --output dist
```

Build combines architectures, signs the extension before the app, verifies signatures. Default SIGN_IDENTITY=- is ad-hoc test signing, not Developer ID or notarization. Do not disable Gatekeeper or remove quarantine. Production signing needs separate configuration.

NSItemProvider temporary files are copied inside callbacks. Staging streams through SHA-256; Ready is committed atomically after successful writes. Receipt URLs carry a UUID resolved inside Ready; launching the receipt is best effort after saving.

```sh
npm test
python -m unittest discover -s scripts -p 'test_*.py' -v
python -m unittest discover -s skills/wechat-chat-select/scripts -p 'test_*.py' -v
```

Set CHAT_RECEIVER_EXE to enable native import tests. Mac CI runs on macos-15 (ARM64) and macos-15-intel, including provider handling, Python contract, registration and installer integration. The universal app is retained as a workflow artifact.

## Publish

1. Align npm, Windows x.y.z.0, Mac x.y.z/build number and bootstrap versions.
2. Package both platforms to the same output directory. Mac executable ZIP modes are explicit, so packaging an unmodified downloaded Mac app on Windows works. Never modify signed files.
3. Run `python scripts/assemble-release.py --output dist`, then `npm pack --pack-destination dist` to create the GitHub-hosted npm installer with pinned archive hashes.
4. Generate SHA256SUMS.txt for ZIPs, tarball, release.json and install.ps1. Review allowed payloads and diffs for private data. Outer bootstrap is outside ZIPs to avoid checksum cycles.
5. Commit source/hashes, push, tag and publish a prerelease with both ZIPs, tarball, checksums, release.json and install.ps1.
6. Test the exact public npx URL on Windows and both Mac runners. GUI, real WeChat, security confirmation and Agent sessions remain separate tests.

The installer verifies before execution, preserves conflicting skills, and detects OS/architecture. Ordinary user home avoids Windows AppData redirection. Use --bundle with a verified extracted release for offline tests.
