[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BundleRoot,
    [string]$InstallRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.wechat-connect-agent'),
    [string]$AgentHome = [Environment]::GetFolderPath('UserProfile'),
    [switch]$NonInteractive,
    [switch]$InstallPython,
    [switch]$TrustCertificate,
    [switch]$ReplaceExistingSkill,
    [switch]$SkillsOnly,
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$expectedSigner = '9AB5B045406F74CC726D6F583F85AC0C02958BB1'

function Confirm-Step([string]$Question, [bool]$Explicit) {
    if ($Explicit) { return $true }
    if ($NonInteractive) { return $false }
    return (Read-Host ($Question + ' [y/N]')) -match '^(y|yes)$'
}

function Get-PythonCommand {
    foreach ($name in @('python','py','python3')) {
        $candidate = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (!$candidate -or $candidate.Source -like '*\Microsoft\WindowsApps\*') { continue }
        $arguments = @()
        if ($name -eq 'py') { $arguments += '-3' }
        $arguments += '-c', 'import sys; print(sys.executable); sys.exit(0 if sys.version_info >= (3,9) else 1)'
        $result = & $candidate.Source @arguments 2>$null
        if ($LASTEXITCODE -eq 0) { return [string](@($result)[-1]) }
    }
    $known = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python314\python.exe'
    if (Test-Path -LiteralPath $known) {
        & $known -c 'import sys; sys.exit(0 if sys.version_info >= (3,9) else 1)'
        if ($LASTEXITCODE -eq 0) { return $known }
    }
    return $null
}

function Test-Bundle([string]$Root) {
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $listing = Get-Content -LiteralPath (Join-Path $rootPath 'files.sha256.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (!@($listing.PSObject.Properties).Count) { throw 'The bundle file list is empty.' }
    foreach ($entry in $listing.PSObject.Properties) {
        if ([IO.Path]::IsPathRooted($entry.Name) -or $entry.Name -match '(^|[/\\])\.\.([/\\]|$)' -or $entry.Name.Contains(':')) {
            throw 'Invalid bundle file path.'
        }
        $path = [IO.Path]::GetFullPath((Join-Path $rootPath $entry.Name))
        if (!$path.StartsWith($rootPath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'File outside bundle.' }
        if (!(Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne [string]$entry.Value) {
            throw ('Bundle file missing or modified: ' + $entry.Name)
        }
    }
}

if ($env:OS -ne 'Windows_NT') { throw 'This PowerShell installer requires Windows x64. Use the unified npx command on macOS.' }
if (![Environment]::Is64BitProcess -or [Environment]::OSVersion.Version.Build -lt 19041) {
    throw 'Open 64-bit Windows PowerShell on Windows 10 build 19041 or newer / Windows 11.'
}
if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
    throw 'This release has only been built and tested for x64 Windows; ARM64 is not supported.'
}
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (!$CheckOnly -and !$SkillsOnly -and $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run the installer from a normal, non-administrator PowerShell window. Only certificate trust is elevated separately.'
}
$framework = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue
if (!$framework -or $framework.Release -lt 528040) { throw '.NET Framework 4.8 or newer is required.' }
$bundle = (Resolve-Path -LiteralPath $BundleRoot).Path
Test-Bundle $bundle
$metadata = Get-Content -LiteralPath (Join-Path $bundle 'bundle.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($metadata.version -notmatch '^\d+\.\d+\.\d+$' -or $metadata.platform -ne 'windows-x64') { throw 'Unsupported bundle version or platform.' }
$buildRoot = Join-Path $bundle 'receiver-windows'
$buildInfo = Get-Content -LiteralPath (Join-Path $buildRoot 'build-info.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($buildInfo.version -ne $metadata.version -or $buildInfo.thumbprint -ne $expectedSigner) { throw 'Unexpected version or signing certificate.' }
$certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new((Join-Path $buildRoot 'AgentChatReceiver.cer'))
try {
    if ($certificate.Thumbprint -ne $expectedSigner -or $certificate.Subject -ne 'CN=Agent Chat Receiver') { throw 'Unexpected certificate.' }
    if ($certificate.NotAfter -le (Get-Date)) { throw 'The signing certificate has expired. Obtain a newer release.' }
} finally { $certificate.Dispose() }
$trusted = Test-Path -LiteralPath ('Cert:\LocalMachine\TrustedPeople\' + $expectedSigner)
$python = Get-PythonCommand
$installPath = [IO.Path]::GetFullPath((Join-Path $InstallRoot ('versions\' + $metadata.version)))
$source = Join-Path $installPath 'skills\wechat-chat-select'
$agentRoot = [IO.Path]::GetFullPath($AgentHome)
$targets = @('.agents\skills\wechat-chat-select', '.claude\skills\wechat-chat-select')
$conflicts = @()
foreach ($relative in $targets) {
    $target = Join-Path $agentRoot $relative
    $item = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.LinkType -ne 'Junction' -or [string]$item.Target -ne $source)) { $conflicts += $target }
}
if ($CheckOnly) {
    [pscustomobject]@{version=$metadata.version; python=$python; certificateTrusted=$trusted; installPath=$installPath; existingSkills=$conflicts; checked=$true} | ConvertTo-Json
    return
}
if ($conflicts.Count -and !(Confirm-Step ('Back up and replace these existing skills: ' + ($conflicts -join ', ')) $ReplaceExistingSkill)) {
    throw 'Existing skills were not changed. Re-run with -ReplaceExistingSkill after reviewing their paths.'
}
if (!$python) {
    if (!(Confirm-Step 'Python 3.9+ is missing. Install Python 3.14 for this user using winget?' $InstallPython)) {
        throw 'Install Python 3.9+ and re-run, or authorize -InstallPython.'
    }
    $winget = Get-Command winget -CommandType Application -ErrorAction SilentlyContinue
    if (!$winget) { throw 'winget is unavailable. Install Python from https://www.python.org/downloads/windows/ and re-run.' }
    & $winget.Source install --exact --id Python.Python.3.14 --source winget --scope user --accept-source-agreements --accept-package-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) { throw 'Python installation did not succeed. No receiver or skill was installed.' }
    $python = Get-PythonCommand
    if (!$python) { throw 'Python was installed but could not be found. Reopen PowerShell and re-run.' }
}
if (!$SkillsOnly -and !$trusted) {
    Write-Host 'The receiver uses a self-signed, non-CA code-signing certificate.'
    Write-Host ('Publisher: CN=Agent Chat Receiver; SHA-1 thumbprint: ' + $expectedSigner)
    Write-Host 'Trust location: LocalMachine\TrustedPeople (all users). The Root store is never modified.'
    if (!(Confirm-Step 'Trust this exact certificate? Windows will ask for administrator approval.' $TrustCertificate)) {
        throw 'Certificate trust was not authorized. Nothing was installed.'
    }
    $trustScript = Join-Path $bundle 'skills\wechat-chat-select\receiver\trust-machine.ps1'
    $resultPath = Join-Path $bundle ('trust-result-' + [Guid]::NewGuid().ToString('N') + '.json')
    # Encode a fixed command with individually quoted paths; no permanent execution-policy change.
    function Quote-Ps([string]$Value) { return "'" + $Value.Replace("'", "''") + "'" }
    $command = '& ([scriptblock]::Create([IO.File]::ReadAllText(' + (Quote-Ps $trustScript) + '))) -BuildDirectory ' +
        (Quote-Ps $buildRoot) + ' -ExpectedThumbprint ' + (Quote-Ps $expectedSigner) + ' -ResultPath ' + (Quote-Ps $resultPath)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $trustProcess = Start-Process -FilePath $powershell -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile','-EncodedCommand',$encoded) -Wait -PassThru
    if ($trustProcess.ExitCode -ne 0 -or !(Test-Path -LiteralPath $resultPath)) { throw 'Certificate trust did not complete.' }
    $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (!$result.ok -or !(Test-Path -LiteralPath ('Cert:\LocalMachine\TrustedPeople\' + $expectedSigner))) { throw 'Certificate trust could not be verified.' }
}
if (!$SkillsOnly) {
    $current = Get-AppxPackage -Name 'AgentChat.Receiver'
    if ($current -and [version]$current.Version -gt [version]$buildInfo.packageVersion) { throw 'A newer receiver is already installed; refusing to downgrade it.' }
    $receiverInstall = [scriptblock]::Create([IO.File]::ReadAllText((Join-Path $bundle 'skills\wechat-chat-select\receiver\install.ps1')))
    & $receiverInstall -BuildDirectory $buildRoot
}
if (Test-Path -LiteralPath $installPath) {
    Test-Bundle $installPath
    $originalList = Get-FileHash -LiteralPath (Join-Path $bundle 'files.sha256.json') -Algorithm SHA256
    $installedList = Get-FileHash -LiteralPath (Join-Path $installPath 'files.sha256.json') -Algorithm SHA256
    if ($originalList.Hash -ne $installedList.Hash) { throw 'This version directory contains a different build; preserved without overwriting.' }
} else {
    New-Item -ItemType Directory -Path (Split-Path -Parent $installPath) -Force | Out-Null
    Copy-Item -LiteralPath $bundle -Destination $installPath -Recurse
    Test-Bundle $installPath
}
$backupRoot = Join-Path $agentRoot ('.wechat-connect-agent-skill-backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N'))
foreach ($relative in $targets) {
    $target = [IO.Path]::GetFullPath((Join-Path $agentRoot $relative))
    if (!$target.StartsWith($agentRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected skill destination.' }
    $item = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'Junction' -and [string]$item.Target -eq $source) { continue }
    if ($item) {
        $backup = [IO.Path]::GetFullPath((Join-Path $backupRoot $relative))
        if (!$backup.StartsWith([IO.Path]::GetFullPath($backupRoot).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected backup destination.' }
        New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
        Move-Item -LiteralPath $target -Destination $backup
        Write-Host ('Previous skill preserved at: ' + $backup)
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    New-Item -ItemType Junction -Path $target -Target $source | Out-Null
}
$receipt = [ordered]@{version=$metadata.version; installedAt=[DateTime]::UtcNow.ToString('o'); skill=$source; python=$python; receiverInstalled=(!$SkillsOnly); inbox=(Join-Path ([Environment]::GetFolderPath('UserProfile')) '.agent-chat-receiver\Inbox')}
[IO.File]::WriteAllText((Join-Path $InstallRoot 'installed.json'), ($receipt | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Host ('Installed WechatConnectAgent ' + $metadata.version + '. Restart your Agent session to load wechat-chat-select.')
Write-Host ('Python: ' + $python)
Write-Host ('Inbox: ' + $receipt.inbox)
if ($SkillsOnly) { Write-Host 'Skills-only mode: the Windows share receiver was not installed.' }
$receipt | ConvertTo-Json
