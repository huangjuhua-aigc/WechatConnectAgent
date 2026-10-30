[CmdletBinding()]
param(
    [switch]$DownloadOnly,
    [switch]$NonInteractive,
    [switch]$InstallPython,
    [switch]$TrustCertificate,
    [switch]$ReplaceExistingSkill
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') {
    throw 'This PowerShell entry is for Windows x64. Use the unified npx command on macOS.'
}
# Updated by scripts/package-release.py. The archive hash is pinned, not fetched alongside the download.
$releaseVersion = '0.2.0'
$archiveSha256 = '91e9309b5e5fcb2d7ec84e8da9ddf8d25eff9c039753227c12f25c912a327225'
$assetName = 'WechatConnectAgent-windows-x64-' + $releaseVersion + '.zip'
$url = 'https://github.com/huangjuhua-aigc/WechatConnectAgent/releases/download/v' + $releaseVersion + '/' + $assetName
$downloadRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) ('.wechat-connect-agent\downloads\' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
$archive = Join-Path $downloadRoot $assetName
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Write-Host ('Downloading WechatConnectAgent ' + $releaseVersion + ' for Windows x64...')
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive -TimeoutSec 180
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $archiveSha256) {
    throw ('Download hash mismatch. Nothing was installed. Download retained at: ' + $archive)
}
$bundle = Join-Path $downloadRoot 'bundle'
Expand-Archive -LiteralPath $archive -DestinationPath $bundle
Write-Host ('Verified SHA-256: ' + $archiveSha256)
if ($DownloadOnly) {
    Write-Output $bundle
    return
}
# Evaluate the verified local script without changing the user's execution policy.
$setup = [scriptblock]::Create([IO.File]::ReadAllText((Join-Path $bundle 'setup.ps1')))
& $setup -BundleRoot $bundle -NonInteractive:$NonInteractive -InstallPython:$InstallPython `
    -TrustCertificate:$TrustCertificate -ReplaceExistingSkill:$ReplaceExistingSkill
