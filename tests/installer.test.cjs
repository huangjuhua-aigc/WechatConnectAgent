'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { platformKey, digest, verifyBundle, psQuote } = require('../lib/common.cjs');
const { parseArgs } = require('../lib/install.cjs');

test('automatic OS/architecture selection rejects unsupported and emulated Windows ARM', () => {
  assert.equal(platformKey('win32', 'x64', {}), 'windows-x64');
  for (const arch of ['arm64', 'x64']) assert.equal(platformKey('darwin', arch, {}), 'macos-universal');
  for (const args of [['win32', 'arm64', {}], ['win32', 'x64', { PROCESSOR_ARCHITEW6432: 'ARM64' }], ['linux', 'x64', {}]]) assert.throws(() => platformKey(...args), /Unsupported/);
});
test('argument parser does not accept platform overrides or missing paths', () => {
  assert.equal(parseArgs(['--non-interactive', '--no-open'])['no-open'], true);
  assert.throws(() => parseArgs(['--platform', 'macos']), /Unknown/);
  assert.throws(() => parseArgs(['--bundle']), /requires/);
  assert.equal(psQuote("a'b $c `d"), "'a''b $c `d'");
});
function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'wechat-installer-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const files = { 'bundle.json': JSON.stringify({ version: '0.2.0', platform: 'macos-universal' }), 'test.txt': 'synthetic' };
  const listing = {};
  for (const [name, contents] of Object.entries(files)) { fs.writeFileSync(path.join(root, name), contents); listing[name] = digest(contents); }
  fs.writeFileSync(path.join(root, 'files.sha256.json'), JSON.stringify(listing));
  return { root, listing };
}
test('integrity verification catches content corruption and platform mismatch', t => {
  const { root } = fixture(t);
  verifyBundle(root, 'macos-universal', '0.2.0');
  assert.throws(() => verifyBundle(root, 'windows-x64', '0.2.0'), /mismatch/);
  fs.writeFileSync(path.join(root, 'test.txt'), 'changed');
  assert.throws(() => verifyBundle(root, 'macos-universal', '0.2.0'), /modified/);
});
test('unlisted files and traversal are rejected before executing anything', t => {
  const { root, listing } = fixture(t);
  fs.writeFileSync(path.join(root, 'extra.exe'), 'unexpected');
  assert.throws(() => verifyBundle(root, 'macos-universal', '0.2.0'), /Unlisted/);
  listing['../escape'] = digest('anything');
  fs.writeFileSync(path.join(root, 'files.sha256.json'), JSON.stringify(listing));
  assert.throws(() => verifyBundle(root, 'macos-universal', '0.2.0'), /Invalid/);
});
test('symlink payloads are rejected', { skip: process.platform === 'win32' }, t => {
  const { root } = fixture(t);
  fs.symlinkSync('test.txt', path.join(root, 'linked.txt'));
  assert.throws(() => verifyBundle(root, 'macos-universal', '0.2.0'), /Linked/);
});
