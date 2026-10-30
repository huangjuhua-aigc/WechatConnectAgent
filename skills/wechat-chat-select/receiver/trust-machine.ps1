[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BuildDirectory,
    [Parameter(Mandatory=$true)][string]$ExpectedThumbprint,
    [Parameter(Mandatory=$true)][string]$ResultPath
)
$ErrorActionPreference = 'Stop'
try {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator approval is required for the LocalMachine TrustedPeople store.'
    }
    $certificateFile = Join-Path (Resolve-Path -LiteralPath $BuildDirectory).Path 'AgentChatReceiver.cer'
    $cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($certificateFile)
    try {
        if ($cert.Subject -ne 'CN=Agent Chat Receiver' -or $cert.Thumbprint -ne $ExpectedThumbprint) {
            throw 'The certificate does not match the specifically authorized publisher and thumbprint.'
        }
        $constraints = $cert.Extensions | Where-Object {$_.Oid.Value -eq '2.5.29.19'}
        $usage = $cert.Extensions | Where-Object {$_.Oid.Value -eq '2.5.29.37'}
        if (!$constraints -or $constraints.CertificateAuthority -or !$usage -or
            @($usage.EnhancedKeyUsages | Where-Object {$_.Value -eq '1.3.6.1.5.5.7.3.3'}).Count -ne 1) {
            throw 'Expected a non-CA code-signing leaf certificate.'
        }
        $store = 'Cert:\LocalMachine\TrustedPeople'
        Import-Certificate -FilePath $certificateFile -CertStoreLocation $store | Out-Null
        if (!(Test-Path -LiteralPath ($store+'\'+$cert.Thumbprint))) {throw 'The certificate import could not be verified.'}
        $result = @{ok=$true;store=$store;thumbprint=$cert.Thumbprint;rootStoreModified=$false}
    } finally {$cert.Dispose()}
} catch {
    $result = @{ok=$false;error=$_.Exception.Message}
}
$json = $result | ConvertTo-Json
$bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
$output = [IO.File]::Open($ResultPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try {$output.Write($bytes,0,$bytes.Length)} finally {$output.Dispose()}
if (!$result.ok) {throw $result.error}
$json
