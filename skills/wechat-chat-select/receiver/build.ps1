[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory, [switch]$Sign)
$ErrorActionPreference = 'Stop'
$buildRoot = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$compiler = Join-Path $framework 'csc.exe'
$sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
$sdkVersion = Get-ChildItem (Join-Path $sdkRoot 'UnionMetadata') -Directory |
    Where-Object {$_.Name -match '^\d+\.' -and (Test-Path (Join-Path $_.FullName 'Windows.winmd'))} |
    Sort-Object {[version]$_.Name} -Descending | Select-Object -First 1
if (!$sdkVersion) {throw 'Install the Windows 10 SDK (19041 or newer) to build the receiver.'}
$sdkBin = Join-Path $sdkRoot ('bin\'+$sdkVersion.Name+'\x64')
$winmd = Join-Path $sdkVersion.FullName 'Windows.winmd'
$gacRoot = Join-Path $env:WINDIR 'Microsoft.NET\assembly\GAC_MSIL'
$references = @(
    (Join-Path $framework 'System.dll'), (Join-Path $framework 'System.Core.dll'),
    (Join-Path $framework 'System.Web.Extensions.dll'), $winmd,
    (Join-Path $framework 'System.Windows.Forms.dll'), (Join-Path $framework 'System.Drawing.dll'),
    (Join-Path $framework 'System.Runtime.WindowsRuntime.dll')
)
foreach ($assemblyName in @('System.Runtime','System.Runtime.InteropServices.WindowsRuntime')) {
    $assemblyFile = Get-ChildItem (Join-Path $gacRoot $assemblyName) -Recurse -Filter ($assemblyName+'.dll') | Select-Object -First 1
    if (!$assemblyFile) {throw ('Missing framework assembly: '+$assemblyName)}
    $references += $assemblyFile.FullName
}
$compileArgs = @('/nologo','/target:winexe','/platform:x64','/optimize+',
    ('/out:'+(Join-Path $buildRoot 'AgentChatReceiver.exe')),
    ('/win32manifest:'+(Join-Path $PSScriptRoot 'app.manifest')))
$compileArgs += $references | ForEach-Object {'/reference:'+$_}
$compileArgs += (Join-Path $PSScriptRoot 'src\ReceiverCore.cs'),(Join-Path $PSScriptRoot 'src\Program.cs')
$compileArgs += (Join-Path $PSScriptRoot 'src\CompletionDialog.cs')
& $compiler @compileArgs
if ($LASTEXITCODE -ne 0) {throw 'Receiver compilation failed.'}
$config = '<?xml version="1.0"?><configuration><startup><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8" /></startup><System.Windows.Forms.ApplicationConfigurationSection><add key="DpiAwareness" value="PerMonitorV2" /></System.Windows.Forms.ApplicationConfigurationSection></configuration>'
[IO.File]::WriteAllText((Join-Path $buildRoot 'AgentChatReceiver.exe.config'),$config,[Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'THIRD_PARTY_NOTICES.txt') -Destination $buildRoot -Force

$packageStage = Join-Path $buildRoot 'package'
$assets = Join-Path $packageStage 'Assets'
New-Item -ItemType Directory -Path $assets -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'AppxManifest.xml') -Destination $packageStage -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'THIRD_PARTY_NOTICES.txt') -Destination $packageStage -Force
Add-Type -AssemblyName System.Drawing
foreach ($dimension in @(44,150)) {
    $bitmap = [Drawing.Bitmap]::new($dimension,$dimension)
    $canvas = [Drawing.Graphics]::FromImage($bitmap)
    $brush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(31,106,181))
    $pen = [Drawing.Pen]::new([Drawing.Color]::White,[single]($dimension/14.0))
    try {
        $canvas.Clear([Drawing.Color]::Transparent)
        $canvas.FillRectangle($brush,0,0,$dimension,$dimension)
        $canvas.DrawRectangle($pen,[single]($dimension*0.18),[single]($dimension*0.3),[single]($dimension*0.64),[single]($dimension*0.48))
        $canvas.DrawLine($pen,[single]($dimension*0.5),[single]($dimension*0.16),[single]($dimension*0.5),[single]($dimension*0.57))
        $canvas.DrawLine($pen,[single]($dimension*0.36),[single]($dimension*0.43),[single]($dimension*0.5),[single]($dimension*0.57))
        $canvas.DrawLine($pen,[single]($dimension*0.64),[single]($dimension*0.43),[single]($dimension*0.5),[single]($dimension*0.57))
        $bitmap.Save((Join-Path $assets ('Logo'+$dimension+'.png')),[Drawing.Imaging.ImageFormat]::Png)
    } finally {$pen.Dispose();$brush.Dispose();$canvas.Dispose();$bitmap.Dispose()}
}
Copy-Item -LiteralPath $assets -Destination $buildRoot -Recurse -Force
$makePri = Join-Path $sdkBin 'makepri.exe'
if (Test-Path -LiteralPath $makePri) {
    $priConfig = Join-Path $buildRoot 'priconfig.xml'
    & $makePri createconfig /cf $priConfig /dq zh-CN /o | Out-Null
    if ($LASTEXITCODE -ne 0) {throw 'PRI configuration failed.'}
    & $makePri new /pr $packageStage /cf $priConfig /mn (Join-Path $packageStage 'AppxManifest.xml') /of (Join-Path $packageStage 'resources.pri') /o | Out-Null
    if ($LASTEXITCODE -ne 0) {throw 'PRI generation failed.'}
    Copy-Item -LiteralPath (Join-Path $packageStage 'resources.pri') -Destination $buildRoot -Force
}
$packagePath = Join-Path $buildRoot 'AgentChatReceiver.msix'
function Build-Package {
    Copy-Item -LiteralPath (Join-Path $buildRoot 'AgentChatReceiver.exe'),(Join-Path $buildRoot 'AgentChatReceiver.exe.config') -Destination $packageStage -Force
    $packOutput = & (Join-Path $sdkBin 'makeappx.exe') pack /d $packageStage /p $packagePath /o 2>&1
    if ($LASTEXITCODE -ne 0) {$packOutput | Write-Output; throw 'MSIX packaging failed.'}
}

if ($Sign) {
    # Generate files only. Trust stores and machine policy are never changed here.
    $privateDir = Join-Path $buildRoot 'private'
    New-Item -ItemType Directory -Path $privateDir -Force | Out-Null
    $keyPath = Join-Path $privateDir 'signing.pfx'
    $publicPath = Join-Path $buildRoot 'AgentChatReceiver.cer'
    if (!(Test-Path -LiteralPath $keyPath)) {
        $rsa = [Security.Cryptography.RSA]::Create(2048)
        try {
            $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=Agent Chat Receiver',$rsa,
                [Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false,$false,0,$true))
            $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new([Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature,$true))
            $oids = [Security.Cryptography.OidCollection]::new()
            [void]$oids.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))
            $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($oids,$true))
            $cert = $request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-5),[DateTimeOffset]::UtcNow.AddYears(1))
            try {
                [IO.File]::WriteAllBytes($keyPath,$cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx,''))
                [IO.File]::WriteAllBytes($publicPath,$cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
            } finally {$cert.Dispose()}
        } finally {$rsa.Dispose()}
    }
    & (Join-Path $sdkBin 'signtool.exe') sign /fd SHA256 /f $keyPath (Join-Path $buildRoot 'AgentChatReceiver.exe') | Out-Null
    if ($LASTEXITCODE -ne 0) {throw 'Executable signing failed.'}
    Build-Package
    & (Join-Path $sdkBin 'signtool.exe') sign /fd SHA256 /f $keyPath $packagePath | Out-Null
    if ($LASTEXITCODE -ne 0) {throw 'Package signing failed.'}
    $publicCert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($publicPath)
    $manifestData = [xml](Get-Content -LiteralPath (Join-Path $packageStage 'AppxManifest.xml') -Raw -Encoding UTF8)
    $packageVersion = [string]$manifestData.Package.Identity.Version
    $buildInfo = [ordered]@{version=([version]$packageVersion).ToString(3);packageVersion=$packageVersion;packaging='msix';package='AgentChatReceiver.msix';certificate='AgentChatReceiver.cer';thumbprint=$publicCert.Thumbprint;
        packageSha256=(Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash;
        executableSha256=(Get-FileHash -LiteralPath (Join-Path $buildRoot 'AgentChatReceiver.exe') -Algorithm SHA256).Hash}
    $buildJson = $buildInfo | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $buildRoot 'build-info.json'),$buildJson,[Text.UTF8Encoding]::new($false))
    $buildJson
    $publicCert.Dispose()
} else { Build-Package; [pscustomobject]@{build=$buildRoot;package=$packagePath;signed=$false}|ConvertTo-Json }
