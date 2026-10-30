[CmdletBinding()]
param([switch]$MigrateLegacyCodex)
$ErrorActionPreference = 'Stop'
$skillSource = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$userRoot = [Environment]::GetFolderPath('UserProfile')
$skillName = 'wechat-chat-select'
$legacy = Join-Path $userRoot '.codex\skills\wechat-chat-select'
$results = @()
if ($MigrateLegacyCodex -and (Test-Path -LiteralPath $legacy)) {
    $legacyItem = Get-Item -LiteralPath $legacy
    if ($legacyItem.LinkType) {throw 'Legacy Codex skill is already a link; inspect it before migration.'}
    $resolvedLegacy = (Resolve-Path -LiteralPath $legacy).Path
    $expectedLegacy = [IO.Path]::GetFullPath((Join-Path $userRoot '.codex\skills\wechat-chat-select'))
    if ($resolvedLegacy -ne $expectedLegacy -or $resolvedLegacy -eq $skillSource) {throw 'Unexpected source for legacy migration.'}
    $backupRoot = Join-Path $userRoot '.codex\skill-backups'
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $backup = [IO.Path]::GetFullPath((Join-Path $backupRoot ('wechat-chat-select-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))))
    if (!$backup.StartsWith([IO.Path]::GetFullPath($backupRoot)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {throw 'Invalid backup path.'}
    Move-Item -LiteralPath $resolvedLegacy -Destination $backup -ErrorAction Stop
    $results += [pscustomobject]@{kind='legacy-backup';path=$backup}
}
# Codex and current Kimi Code both read the shared user directory.
# Claude Code reads its own personal directory. Both links point to one source.
foreach ($relativeRoot in @('.agents\skills','.claude\skills')) {
    $agentRoot = Join-Path $userRoot $relativeRoot
    New-Item -ItemType Directory -Path $agentRoot -Force | Out-Null
    $destination = Join-Path $agentRoot $skillName
    if (Test-Path -LiteralPath $destination) {
        $existing = Get-Item -LiteralPath $destination
        if ($existing.LinkType -ne 'Junction' -or [string]$existing.Target -ne $skillSource) {
            throw ('Refusing to overwrite a different existing skill: '+$destination)
        }
    } else { New-Item -ItemType Junction -Path $destination -Target $skillSource | Out-Null }
    $results += [pscustomobject]@{kind='skill-link';path=$destination;target=$skillSource}
}
$results | ConvertTo-Json
