param([switch] $Unsigned)

$ErrorActionPreference = 'Stop'
$application = 'build/windows/x64/runner/Release/periodify.exe'
if (-not (Test-Path -LiteralPath $application -PathType Leaf)) { throw 'Run flutter build windows --release before packaging.' }
$version = $env:TAG -replace '^v', ''
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'A version tag is required to package Windows.' }
$compiler = 'C:/Program Files (x86)/Inno Setup 6/ISCC.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
  $compiler = (Get-Command ISCC.exe -ErrorAction Stop).Source
}

function Build-Installer([string] $Basename) {
  & $compiler "/DAppVersion=$version" "/DInstallerBasename=$Basename" packaging/windows.iss
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath "artifacts/$Basename.exe" -PathType Leaf)) {
    throw 'Installer build failed'
  }
}

if ($Unsigned) {
  Build-Installer 'periodify-windows-unsigned'
  $signature = Get-AuthenticodeSignature -LiteralPath 'artifacts/periodify-windows-unsigned.exe'
  if ($signature.Status -ne 'NotSigned') { throw 'Unexpected Windows preview signature status' }
  return
}

if (-not $env:WINDOWS_PFX_BASE64 -or -not $env:WINDOWS_PFX_PASSWORD) { throw 'Missing Windows signing secrets.' }
$pfxPath = Join-Path $env:RUNNER_TEMP 'periodify.pfx'
try {
  [IO.File]::WriteAllBytes($pfxPath, [Convert]::FromBase64String($env:WINDOWS_PFX_BASE64))
  $certificate = Import-PfxCertificate -FilePath $pfxPath -CertStoreLocation Cert:\CurrentUser\My -Password (ConvertTo-SecureString $env:WINDOWS_PFX_PASSWORD -AsPlainText -Force)
  $signTool = (Get-ChildItem 'C:/Program Files (x86)/Windows Kits/10/bin' -Filter signtool.exe -Recurse | Where-Object FullName -Match '\\x64\\' | Sort-Object FullName | Select-Object -Last 1).FullName
  & $signTool sign /sha1 $certificate.Thumbprint /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 $application
  if ($LASTEXITCODE -ne 0) { throw 'Application signing failed' }
  & $signTool verify /pa $application
  if ($LASTEXITCODE -ne 0) { throw 'Application signature verification failed' }
  Build-Installer 'periodify-windows'
  & $signTool sign /sha1 $certificate.Thumbprint /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 artifacts/periodify-windows.exe
  if ($LASTEXITCODE -ne 0) { throw 'Installer signing failed' }
  & $signTool verify /pa artifacts/periodify-windows.exe
  if ($LASTEXITCODE -ne 0) { throw 'Signature verification failed' }
} finally {
  Remove-Item -LiteralPath $pfxPath -ErrorAction SilentlyContinue
  if ($certificate) { Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($certificate.Thumbprint)" -ErrorAction SilentlyContinue }
}
