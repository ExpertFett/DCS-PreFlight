<#
  Build-Package.ps1 - produce the distributable artifacts in .\dist
    1. DCS-Preflight-<ver>-portable.zip   (unzip and run)
    2. DCS-Preflight-Setup.exe            (if Inno Setup is installed)

  Deliberately excludes apps.json - that is personal config, and a fresh
  install auto-detects the user's own programs on first run.
#>
[CmdletBinding()]
param([string]$Version = '1.0.0')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dist = Join-Path $root 'dist'
$stage = Join-Path $env:TEMP ('pfpkg_' + [System.IO.Path]::GetRandomFileName())

$payload = @(
    'DCS-Preflight.ps1', 'DCS-Preflight-Manager.ps1',
    'Native.ps1', 'Common.ps1',
    'DCS-Preflight.bat', 'DCS-Preflight-Manager.bat',
    'README.md'
)

Write-Host 'Staging files...' -ForegroundColor Cyan
New-Item -ItemType Directory -Path $stage -Force | Out-Null
foreach ($f in $payload) {
    $src = Join-Path $root $f
    if (-not (Test-Path -LiteralPath $src)) { throw "Missing payload file: $f" }
    Copy-Item -LiteralPath $src -Destination $stage -Force
}

if (-not (Test-Path -LiteralPath $dist)) { New-Item -ItemType Directory -Path $dist -Force | Out-Null }

# ---- portable zip (forward-slash entries; Compress-Archive writes backslashes) ----
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = Join-Path $dist "DCS-Preflight-$Version-portable.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in $payload) {
        $entry = $zip.CreateEntry("DCS-Preflight/$f", [System.IO.Compression.CompressionLevel]::Optimal)
        $in  = [System.IO.File]::OpenRead((Join-Path $stage $f))
        $out = $entry.Open()
        try { $in.CopyTo($out) } finally { $out.Dispose(); $in.Dispose() }
    }
} finally { $zip.Dispose() }
Write-Host "  zip  -> $zipPath" -ForegroundColor Green

# ---- Inno Setup installer (optional) ----
$iscc = $null
foreach ($c in @("${env:LOCALAPPDATA}\Programs\Inno Setup 6\ISCC.exe",
                 "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
                 "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
                 "${env:ProgramFiles(x86)}\Inno Setup 5\ISCC.exe")) {
    if (Test-Path -LiteralPath $c) { $iscc = $c; break }
}
if ($iscc) {
    Write-Host 'Compiling installer...' -ForegroundColor Cyan
    & $iscc "/DAppVersion=$Version" (Join-Path $root 'installer.iss') | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  exe  -> $(Join-Path $dist 'DCS-Preflight-Setup.exe')" -ForegroundColor Green
    } else {
        Write-Host "  Inno Setup returned $LASTEXITCODE" -ForegroundColor Yellow
    }
} else {
    Write-Host '  Inno Setup not found - skipped the .exe installer (zip is ready).' -ForegroundColor Yellow
}

Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Get-ChildItem -LiteralPath $dist | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,2)}}
