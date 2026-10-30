# Development and release

The self-contained skill lives at `skills/wechat-chat-select`. The receiver is C# 5 / .NET Framework 4.8 and uses public Windows Share APIs. The Python tools use only the standard library (Python 3.9+).

## Tests

```powershell
python -m unittest discover -s skills/wechat-chat-select/scripts -p 'test_*.py' -v
python -m unittest discover -s scripts -p 'test_*.py' -v
```

Without `CHAT_RECEIVER_EXE`, native receiver import tests are skipped. To test the actual executable:

```powershell
$env:CHAT_RECEIVER_EXE = Join-Path (Get-AppxPackage -Name AgentChat.Receiver).InstallLocation 'AgentChatReceiver.exe'
python -m unittest discover -s skills/wechat-chat-select/scripts -p 'test_*.py' -v
```

The installer integration check runs against an extracted release bundle with an isolated home and installation root. It does not import certificates or change the installed MSIX package:

```powershell
python scripts/test_installer.py --bundle <absolute-extracted-bundle>
```

## Build

Use Windows x64, PowerShell 7, .NET Framework 4.8 and Windows SDK 19041 or newer. A standalone dotnet SDK or Visual Studio IDE is not required by the build script.

```powershell
./skills/wechat-chat-select/receiver/build.ps1 -OutputDirectory <private-build-directory> -Sign
```

The first signed build creates a **private signing key** in `<private-build-directory>/private/signing.pfx`. Keep it outside this repository and never publish it. Future builds must reuse that directory/key to update an existing installation. The public certificate can be shipped. A different signing key requires a deliberate publisher/trust migration; do not silently change the installer's pinned certificate.

Self-signed builds are for users who explicitly trust the displayed certificate. A publicly trusted distribution certificate or Store release would require a separate release/signing setup. Never commit certificate-store exports or credentials.

## Package and publish

1. Update the MSIX version and the release version shown in the README, docs and installer.
2. Build the signed receiver. Run the tests against the installed executable and review the actual receipt window.
3. Create an archive from explicitly allowed source and build files:

```powershell
python scripts/package-release.py --build <private-build-directory> --output dist
```

The script generates the Windows ZIP, `SHA256SUMS.txt`, a portable release manifest and release-notes text, and pins the archive hash in `install.ps1`. It rejects private keys and unexpected binary inputs. The outer bootstrap is intentionally outside the ZIP to avoid a checksum cycle; `setup.ps1` inside the ZIP is the local installer. Re-package after any bundled source/docs change, then commit the final source and bootstrap hash together.

4. Test the extracted bundle with `scripts/test_installer.py`. The Windows PowerShell parser must accept all installer scripts. Review `git diff --cached` and the ZIP listing for private data.
5. Commit and push, create the corresponding `v<version>` tag, and publish a GitHub Release with the ZIP, checksum file and manifest. Upload the standalone MSIX and public certificate only if useful; the complete ZIP is the supported installer input.
6. Download from the public release with `install.ps1 -DownloadOnly`, check the same SHA-256, and test the documented installation command. Never describe an unpublished or untested URL as working.

The CI workflow runs parser tests and Python unit tests. A passing CI run does not validate real WeChat sharing, GUI behavior, certificate installation, or other Agents' desktop tools. See the skill's [validation record](../skills/wechat-chat-select/references/validation.md).
