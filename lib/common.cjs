'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

function platformKey(platform = process.platform, arch = process.arch, env = process.env) {
  if (platform === 'win32' && arch === 'x64' &&
      ![env.PROCESSOR_ARCHITECTURE, env.PROCESSOR_ARCHITEW6432].some(v => /^arm64$/i.test(v || ''))) return 'windows-x64';
  if (platform === 'darwin' && ['x64', 'arm64'].includes(arch)) return 'macos-universal';
  throw new Error(`Unsupported system: ${platform}/${arch}. Supported: Windows x64 and macOS Intel/Apple Silicon.`);
}
function run(command, args, options = {}) {
  const env = { ...process.env };
  // PowerShell 7's module path breaks built-in modules in Windows PowerShell 5.
  if (process.platform === 'win32') for (const key of Object.keys(env)) {
    if (key.toLowerCase() === 'psmodulepath') delete env[key];
  }
  const result = spawnSync(command, args, { encoding: 'utf8', env, windowsHide: true, ...options });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${path.basename(command)} failed (${result.status}): ${(result.stderr || '').trim()}`);
  return (result.stdout || '').trim();
}
function powershell(source) {
  const command = path.join(process.env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe');
  return run(command, ['-NoProfile', '-EncodedCommand', Buffer.from(source, 'utf16le').toString('base64')], { stdio: 'inherit' });
}
const psQuote = value => "'" + value.replace(/'/g, "''") + "'";
const digest = data => crypto.createHash('sha256').update(data).digest('hex');
const json = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
const exists = file => { try { fs.lstatSync(file); return true; } catch (e) { if (e.code === 'ENOENT') return false; throw e; } };
function safePath(root, name) {
  if (!name || name.includes('\\') || name.includes(':') || name.startsWith('/') ||
      name.split('/').some(p => !p || p === '.' || p === '..')) throw new Error(`Invalid bundle path: ${name}`);
  const dest = path.resolve(root, ...name.split('/'));
  if (!dest.startsWith(path.resolve(root) + path.sep)) throw new Error('Bundle path escapes its directory');
  return dest;
}
function verifyBundle(root, expectedPlatform, version, allowPythonCache = false) {
  if (fs.lstatSync(root).isSymbolicLink()) throw new Error('Bundle root must not be a symbolic link');
  const listingPath = path.join(root, 'files.sha256.json');
  if (!fs.lstatSync(listingPath).isFile()) throw new Error('Invalid bundle file list');
  const listing = json(listingPath);
  if (!listing || typeof listing !== 'object' || Array.isArray(listing) || !Object.keys(listing).length) throw new Error('Empty bundle file list');
  for (const [name, hash] of Object.entries(listing)) {
    const file = safePath(root, name);
    let segment = root;
    for (const part of name.split('/')) {
      segment = path.join(segment, part);
      if (fs.lstatSync(segment).isSymbolicLink()) throw new Error(`Linked bundle file: ${name}`);
    }
    if (!fs.lstatSync(file).isFile() || !/^[a-f0-9]{64}$/.test(hash) || digest(fs.readFileSync(file)) !== hash) throw new Error(`Bundle file missing or modified: ${name}`);
  }
  // Reject files omitted from the integrity list, including unexpected executable code.
  function walk(folder) {
    for (const entry of fs.readdirSync(folder, { withFileTypes: true })) {
      const file = path.join(folder, entry.name), rel = path.relative(root, file).split(path.sep).join('/');
      if (entry.isSymbolicLink()) throw new Error(`Linked bundle entry: ${rel}`);
      if (entry.isDirectory()) walk(file);
      else if (!entry.isFile() || (rel !== 'files.sha256.json' && !Object.hasOwn(listing, rel) &&
        !(allowPythonCache && /^skills\/wechat-chat-select\/scripts\/__pycache__\/[^/]+\.pyc$/.test(rel)))) throw new Error(`Unlisted bundle file: ${rel}`);
    }
  }
  walk(root);
  if (!Object.hasOwn(listing, 'bundle.json')) throw new Error('Unverified bundle metadata');
  const metadata = json(path.join(root, 'bundle.json'));
  if (metadata.platform !== expectedPlatform || metadata.version !== version) throw new Error('Bundle version or platform mismatch');
  return listing;
}
module.exports = { platformKey, run, powershell, psQuote, digest, json, exists, safePath, verifyBundle };
