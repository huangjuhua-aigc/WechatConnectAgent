'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { run, json, exists, verifyBundle, digest } = require('./common.cjs');
const APP_ID = 'com.wechatconnectagent.receiver';

function appId(app) {
  if (fs.lstatSync(app).isSymbolicLink()) throw new Error(`App destination is a symbolic link: ${app}`);
  return run('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleIdentifier', path.join(app, 'Contents/Info.plist')]);
}
function findPython() {
  const candidates = [...new Set([...(process.env.PATH || '').split(path.delimiter).map(p => path.join(p, 'python3')), '/opt/homebrew/bin/python3', '/usr/local/bin/python3'])];
  for (const candidate of candidates) {
    if (!fs.existsSync(candidate)) continue;
    try {
      // Avoid triggering Apple's command-line tools installation dialog.
      if (fs.realpathSync(candidate) === '/usr/bin/python3') run('/usr/bin/xcode-select', ['-p']);
      return run(candidate, ['-c', 'import sys; print(sys.executable); sys.exit(0 if sys.version_info >= (3,9) else 1)']);
    } catch { /* Try the next real interpreter. */ }
  }
  return null;
}
async function installMac({ bundle, version, options, confirm }) {
  if (Number(run('/usr/bin/sw_vers', ['-productVersion']).split('.')[0]) < 13) throw new Error('macOS 13 or newer is required');
  const home = os.homedir(), root = path.join(home, '.wechat-connect-agent');
  const versionRoot = path.join(root, 'versions', version);
  const source = path.join(versionRoot, 'skills/wechat-chat-select');
  const appSource = path.join(bundle, 'receiver-macos/ChatInbox.app');
  const applications = path.join(home, 'Applications'), app = path.join(applications, 'ChatInbox.app');
  const targets = ['.agents/skills/wechat-chat-select', '.claude/skills/wechat-chat-select'].map(p => path.join(home, p));
  const conflicts = targets.filter(target => exists(target) && !(fs.lstatSync(target).isSymbolicLink() && path.resolve(path.dirname(target), fs.readlinkSync(target)) === source));
  if (conflicts.length && !await confirm(`Back up and replace existing skills: ${conflicts.join(', ')}?`, options, options['replace-existing-skill'])) throw new Error('Existing skills preserved. Re-run with --replace-existing-skill after reviewing these paths.');
  if (appId(appSource) !== APP_ID) throw new Error('Unexpected receiver bundle identifier');
  run('/usr/bin/codesign', ['--verify', '--deep', '--strict', appSource]);
  if (exists(app)) {
    if (appId(app) !== APP_ID) throw new Error('A different app occupies the install path; it was preserved');
    const installedVersion = run('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleShortVersionString', path.join(app, 'Contents/Info.plist')]);
    const numeric = v => v.split('.').reduce((n, p) => n * 10000 + Number(p), 0);
    if (!/^\d+\.\d+\.\d+$/.test(installedVersion) || numeric(installedVersion) > numeric(version)) throw new Error('Refusing to replace a newer or unknown receiver version');
  }
  if (exists(versionRoot)) {
    verifyBundle(versionRoot, 'macos-universal', version, true);
    if (digest(fs.readFileSync(path.join(versionRoot, 'files.sha256.json'))) !== digest(fs.readFileSync(path.join(bundle, 'files.sha256.json')))) throw new Error('This version directory contains a different build; preserved without overwriting');
  }
  let python = findPython();
  if (!python) {
    const brew = ['/opt/homebrew/bin/brew', '/usr/local/bin/brew'].find(p => fs.existsSync(p));
    if (!brew || !await confirm('Python 3.9+ is required. Install Python using your existing Homebrew?', options, options['install-python'])) throw new Error('Install Python 3.9+ from https://www.python.org/downloads/macos/ and re-run, or use --install-python with an existing Homebrew installation.');
    run(brew, ['install', 'python'], { stdio: 'inherit' });
    python = findPython();
    if (!python) throw new Error('Python installation could not be verified');
  }
  fs.mkdirSync(root, { recursive: true, mode: 0o700 });
  const backupRoot = path.join(root, 'backups', new Date().toISOString().replace(/[:.]/g, '-') + '-' + crypto.randomUUID());
  if (!exists(versionRoot)) {
    fs.mkdirSync(path.dirname(versionRoot), { recursive: true, mode: 0o700 });
    run('/usr/bin/ditto', [bundle, versionRoot]);
    verifyBundle(versionRoot, 'macos-universal', version);
  }
  fs.mkdirSync(applications, { recursive: true });
  const staged = path.join(applications, '.ChatInbox-' + crypto.randomUUID() + '.app');
  run('/usr/bin/ditto', [appSource, staged]);
  run('/usr/bin/codesign', ['--verify', '--deep', '--strict', staged]);
  let previous;
  if (exists(app)) {
    fs.mkdirSync(backupRoot, { recursive: true, mode: 0o700 });
    previous = path.join(backupRoot, 'ChatInbox.app');
    fs.renameSync(app, previous);
  }
  try { fs.renameSync(staged, app); }
  catch (error) { if (previous) fs.renameSync(previous, app); throw error; }
  for (const [i, target] of targets.entries()) {
    if (exists(target) && !conflicts.includes(target)) continue;
    if (exists(target)) {
      fs.mkdirSync(backupRoot, { recursive: true, mode: 0o700 });
      const backup = path.join(backupRoot, 'skill-' + i);
      fs.renameSync(target, backup);
      console.log(`Previous skill preserved at: ${backup}`);
    }
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.symlinkSync(source, target, 'dir');
  }
  const inbox = path.join(home, '.agent-chat-receiver/Inbox');
  fs.mkdirSync(inbox, { recursive: true, mode: 0o700 });
  let registered = false;
  try {
    run('/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', ['-f', app]);
    run('/usr/bin/pluginkit', ['-a', path.join(app, 'Contents/PlugIns/ChatInboxShare.appex')]);
    registered = Boolean(run('/usr/bin/pluginkit', ['-m', '-i', APP_ID + '.share']));
  } catch (error) { console.warn(`Registration needs a manual check: ${error.message}`); }
  const receipt = { version, installedAt: new Date().toISOString(), app, skill: source, python, inbox, registered, signing: 'ad-hoc-test' };
  fs.writeFileSync(path.join(root, 'installed.json'), JSON.stringify(receipt, null, 2) + '\n', { mode: 0o600 });
  console.log(`Installed WechatConnectAgent ${version}.\nApp: ${app}\nInbox: ${inbox}\nPython: ${python}\nRestart your Agent session to load wechat-chat-select.`);
  console.log('macOS TEST BUILD: no Developer ID or notarization. First launch may require System Settings > Privacy & Security > Open Anyway. Then enable Chat Inbox (聊天收件箱) in Sharing extensions if absent.\nInstructions: https://github.com/huangjuhua-aigc/WechatConnectAgent/blob/v0.2.0/docs/install-macos.md');
  if (!options['no-open']) {
    try { run('/usr/bin/open', [app]); }
    catch { console.warn(`Open ${app} in Finder and complete the macOS first-launch confirmation.`); }
  }
  return receipt;
}
module.exports = { installMac, findPython };
