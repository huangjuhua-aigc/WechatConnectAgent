'use strict';
// Integration test for disposable macOS CI runners only.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
if (process.platform !== 'darwin' || process.env.GITHUB_ACTIONS !== 'true') throw new Error('Run only on a disposable GitHub macOS runner');
const home = os.homedir();
const old = path.join(home, '.agents/skills/wechat-chat-select');
assert.ok(!fs.existsSync(old), 'Do not overwrite an existing skill');
fs.mkdirSync(old, { recursive: true });
fs.writeFileSync(path.join(old, 'keep.txt'), 'synthetic existing skill');
const args = ['bin/install.cjs', '--bundle', path.resolve(process.argv[2]), '--non-interactive', '--no-open'];
function install(extra, expected) {
  const result = spawnSync(process.execPath, [...args, ...extra], { encoding: 'utf8' });
  console.log(result.stdout, result.stderr);
  assert.equal(result.status, expected);
}
install([], 1);
assert.equal(fs.readFileSync(path.join(old, 'keep.txt'), 'utf8'), 'synthetic existing skill');
assert.ok(!fs.existsSync(path.join(home, 'Applications/ChatInbox.app')));
install(['--replace-existing-skill'], 0);
for (const entry of ['.agents/skills/wechat-chat-select', '.claude/skills/wechat-chat-select']) {
  assert.equal(fs.realpathSync(path.join(home, entry)), path.join(home, '.wechat-connect-agent/versions/0.2.0/skills/wechat-chat-select'));
}
const receipt = JSON.parse(fs.readFileSync(path.join(home, '.wechat-connect-agent/installed.json'), 'utf8'));
assert.equal(receipt.registered, true);
assert.equal(receipt.signing, 'ad-hoc-test');
const identity = spawnSync(path.join(receipt.app, 'Contents/MacOS/ChatInbox'), ['--identity'], { encoding: 'utf8' });
assert.equal(identity.status, 0);
assert.match(identity.stdout, /com.wechatconnectagent.receiver/);
install([], 0);
const backups = path.join(home, '.wechat-connect-agent/backups');
assert.ok(fs.readdirSync(backups).some(d => fs.existsSync(path.join(backups, d, 'skill-0/keep.txt'))));
console.log('Mac installer: conflict preservation, backup, links, identity, registration and reinstall passed.');
