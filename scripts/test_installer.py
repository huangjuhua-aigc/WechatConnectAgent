"""Exercise the real installer in an isolated home without MSIX or certificate changes."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, required=True)
    args = parser.parse_args()
    bundle = args.bundle.resolve()
    if os.name != "nt":
        raise SystemExit("Windows is required for junction and Windows PowerShell checks.")
    powershell = str(Path(os.environ["WINDIR"]) / "System32/WindowsPowerShell/v1.0/powershell.exe")
    # Leave diagnostics intact; never recursively delete a junction target.
    base = Path(tempfile.mkdtemp(prefix="wechat-connect-agent-installer-test-"))
    agent_home, install = base / "home with spaces 'quote", base / "installed with spaces 'quote"
    setup = bundle / "setup.ps1"
    command = [powershell, "-NoProfile", "-File", str(setup), "-BundleRoot", str(bundle),
               "-InstallRoot", str(install), "-AgentHome", str(agent_home), "-SkillsOnly", "-NonInteractive"]
    environment = {key: value for key, value in os.environ.items() if key.upper() != 'PSMODULEPATH'}

    def run(arguments, success=True):
        result = subprocess.run(arguments, text=True, encoding="utf-8", errors="replace", capture_output=True, timeout=45, env=environment)
        if (result.returncode == 0) != success:
            raise AssertionError(result.stdout + result.stderr)
        return result

    old = agent_home / ".agents/skills/wechat-chat-select"
    old.mkdir(parents=True)
    (old / "keep.txt").write_text("existing user skill", encoding="utf-8")
    run(command, success=False)
    assert (old / "keep.txt").read_text() == "existing user skill"
    assert not install.exists(), "Conflict must fail before writing install directory"
    run(command + ["-ReplaceExistingSkill"])
    metadata = json.loads((bundle / "bundle.json").read_text())
    expected = install / "versions" / metadata["version"] / "skills/wechat-chat-select"
    for relative in (".agents/skills/wechat-chat-select", ".claude/skills/wechat-chat-select"):
        assert (agent_home / relative).resolve() == expected.resolve()
        assert (agent_home / relative / "SKILL.md").is_file()
    backups = list((agent_home / ".wechat-connect-agent-skill-backups").rglob("keep.txt"))
    assert len(backups) == 1 and backups[0].read_text() == "existing user skill"
    run(command)
    assert len(list((agent_home / ".wechat-connect-agent-skill-backups").iterdir())) == 1, "Same-version reinstall should be idempotent"
    receipt = json.loads((install / "installed.json").read_text())
    assert not receipt["receiverInstalled"]
    corrupt = base / "corrupt bundle"
    shutil.copytree(bundle, corrupt)
    (corrupt / "receiver-windows/AgentChatReceiver.exe").write_bytes(b"corrupted fixture")
    bad_command = command.copy()
    bad_command[bad_command.index("-BundleRoot") + 1] = str(corrupt)
    run(bad_command, success=False)
    before = hashlib.sha256((expected / "SKILL.md").read_bytes()).hexdigest()
    assert before == hashlib.sha256((bundle / "skills/wechat-chat-select/SKILL.md").read_bytes()).hexdigest()
    print(json.dumps({"ok": True, "checks": ["conflict preserves existing skill", "backup and link creation",
        "paths with spaces and quotes", "same-version reinstall", "corrupt payload rejected", "no receiver installation"],
        "diagnostics": str(base)}, indent=2))


if __name__ == "__main__":
    main()
