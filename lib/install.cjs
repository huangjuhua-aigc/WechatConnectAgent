'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const readline = require('node:readline/promises');
const { platformKey, run, powershell, psQuote, json, verifyBundle } = require('./common.cjs');

async function confirm(question, options, explicit) {
  if (explicit) return true;
  if (options['non-interactive'] || !process.stdin.isTTY) return false;
  const prompt = readline.createInterface({ input: process.stdin, output: process.stdout });
  try { return /^y(es)?$/i.test((await prompt.question(question + ' [y/N] ')).trim()); }
  finally { prompt.close(); }
}
function parseArgs(args) {
  const options = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i] === 'install') continue;
    const key = args[i].replace(/^--/, '');
    if (args[i] === '--bundle') {
      if (!args[i + 1] || args[i + 1].startsWith('--')) throw new Error('--bundle requires a directory');
      options.bundle = path.resolve(args[++i]);
    } else if (['help', 'dry-run', 'download-only', 'non-interactive', 'replace-existing-skill', 'trust-certificate', 'install-python', 'no-open'].includes(key) && args[i].startsWith('--')) options[key] = true;
    else throw new Error(`Unknown argument: ${args[i]}`);
  }
  return options;
}
async function download(asset, destination) {
  if (!/^https:\/\/github\.com\/huangjuhua-aigc\/WechatConnectAgent\/releases\/download\//.test(asset.url) || !/^[a-f0-9]{64}$/.test(asset.sha256)) throw new Error('Release assets have not been configured');
  const response = await fetch(asset.url, { signal: AbortSignal.timeout(180000) });
  if (!response.ok || !response.body) throw new Error(`Download failed: HTTP ${response.status}`);
  const file = fs.openSync(destination, 'wx', 0o600), hash = crypto.createHash('sha256');
  let size = 0;
  try {
    for await (const chunk of response.body) {
      size += chunk.length;
      if (size > 512 * 1024 * 1024) throw new Error('Release exceeds the download size limit');
      hash.update(chunk);
      let offset = 0;
      while (offset < chunk.length) offset += fs.writeSync(file, chunk, offset, chunk.length - offset);
    }
    fs.fsyncSync(file);
  } finally { fs.closeSync(file); }
  if (hash.digest('hex') !== asset.sha256) throw new Error('Downloaded archive SHA-256 does not match the pinned release');
}
async function main(args) {
  const options = parseArgs(args);
  if (options.help) {
    console.log('wechat-connect-agent [install] [--dry-run] [--download-only] [--non-interactive]\n  [--replace-existing-skill] [--install-python] [--trust-certificate] [--no-open]\n  [--bundle <extracted release directory>]\nSystem and architecture are detected automatically.');
    return;
  }
  const platform = platformKey();
  const version = require('../package.json').version;
  const assets = json(path.join(__dirname, '../release-assets.json'));
  if (assets.version !== version || !assets.assets[platform]) throw new Error('Inconsistent release metadata');
  console.log(`WechatConnectAgent ${version}: detected ${process.platform}/${process.arch} -> ${platform}`);
  const asset = assets.assets[platform];
  if (options['dry-run']) { console.log(JSON.stringify({ version, platform, ...asset }, null, 2)); return; }
  let bundle = options.bundle;
  if (!bundle) {
    const downloads = path.join(os.homedir(), '.wechat-connect-agent', 'downloads');
    fs.mkdirSync(downloads, { recursive: true, mode: 0o700 });
    const session = fs.mkdtempSync(path.join(downloads, version + '-'));
    const archive = path.join(session, 'release.zip');
    console.log('Downloading and verifying the native receiver and skill...');
    await download(asset, archive);
    if (options['download-only']) { console.log(`Verified archive: ${archive}`); return; }
    bundle = path.join(session, 'bundle');
    if (platform === 'windows-x64') powershell(`$ErrorActionPreference='Stop'; Expand-Archive -LiteralPath ${psQuote(archive)} -DestinationPath ${psQuote(bundle)}`);
    else run('/usr/bin/ditto', ['-x', '-k', archive, bundle]);
  }
  verifyBundle(bundle, platform, version);
  if (platform === 'windows-x64') {
    const switches = [];
    for (const [name, ps] of Object.entries({ 'non-interactive': 'NonInteractive', 'replace-existing-skill': 'ReplaceExistingSkill', 'trust-certificate': 'TrustCertificate', 'install-python': 'InstallPython' })) if (options[name]) switches.push('-' + ps);
    powershell(`$ErrorActionPreference='Stop'; & ([scriptblock]::Create([IO.File]::ReadAllText(${psQuote(path.join(bundle, 'setup.ps1'))}))) -BundleRoot ${psQuote(bundle)} ${switches.join(' ')}`);
  } else await require('./install-macos.cjs').installMac({ bundle, version, options, confirm });
}
module.exports = { main, parseArgs, download };
