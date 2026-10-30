[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BuildDirectory
)
$ErrorActionPreference = 'Stop'
$buildRoot = (Resolve-Path -LiteralPath $BuildDirectory).Path
$buildInfo = Get-Content -LiteralPath (Join-Path $buildRoot 'build-info.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$package = Join-Path $buildRoot 'AgentChatReceiver.msix'
$executable = Join-Path $buildRoot 'AgentChatReceiver.exe'
$certificateFile = Join-Path $buildRoot 'AgentChatReceiver.cer'
if ((Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash -ne $buildInfo.packageSha256 -or
    (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash -ne $buildInfo.executableSha256) {
    throw 'Build hashes do not match. Rebuild before installing.'
}
$cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($certificateFile)
try {
    if ($cert.Subject -ne 'CN=Agent Chat Receiver' -or $cert.Thumbprint -ne $buildInfo.thumbprint) {throw 'Unexpected signing certificate.'}
    $signature = Get-AuthenticodeSignature -LiteralPath $executable
    if (!$signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $cert.Thumbprint) {throw 'Executable signer does not match the package publisher.'}
    $trusted = Test-Path -LiteralPath ('Cert:\LocalMachine\TrustedPeople\'+$cert.Thumbprint)
    if (!$trusted) {
        throw ('MSIX installation requires explicitly trusting this code-signing leaf certificate in LocalMachine\TrustedPeople: '+$cert.Thumbprint+'. Review the .cer, obtain authorization and run trust-machine.ps1 as administrator before retrying. No trust setting was changed.')
    }
    if ($buildInfo.packaging -ne 'msix') {throw 'Rebuild the receiver as a complete MSIX package.'}
    Add-AppxPackage -Path $package -ErrorAction Stop
    $registered = Get-AppxPackage -Name 'AgentChat.Receiver'
    if (!$registered) {throw 'Package registration was not found after installation.'}
    if ([string]$registered.Version -ne $buildInfo.packageVersion) {throw 'The installed package version does not match the build.'}
    $installRoot = $registered.InstallLocation
    $diagnostics = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.agent-chat-receiver\Diagnostics'
    New-Item -ItemType Directory -Path $diagnostics -Force | Out-Null
    $resultPath = Join-Path $diagnostics ('identity-'+[Guid]::NewGuid().ToString('N')+'.json')
    $identityProcess = Start-Process -FilePath (Join-Path $installRoot 'AgentChatReceiver.exe') -ArgumentList @('--identity','--result',('"'+$resultPath+'"')) -WindowStyle Hidden -PassThru
    if (!$identityProcess.WaitForExit(10000)) {throw ('Runtime identity verification timed out. Process: '+$identityProcess.Id)}
    if ($identityProcess.ExitCode -ne 0) {throw ('Runtime identity verification failed; inspect '+$resultPath)}
    $identity = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (!$identity.ok -or $identity.name -ne 'AgentChat.Receiver') {throw 'Unexpected runtime package identity.'}
    [pscustomobject]@{installed=$true;package=$registered.PackageFullName;path=$installRoot;displayName='Chat Inbox';
        runtimeIdentityVerified=$true;nativeShareTested=$false;inbox=(Join-Path ([Environment]::GetFolderPath('UserProfile')) '.agent-chat-receiver\Inbox')} | ConvertTo-Json
} finally {$cert.Dispose()}
