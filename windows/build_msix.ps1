# Builds a signed, installable MSIX package for Narraity.
#
# Bypasses the `msix` pub package's own bundled MakeAppx.exe/signtool.exe --
# on this machine (and potentially other newer Windows/SDK installs) those
# bundled binaries fail with "side-by-side configuration is incorrect", a
# WinSxS mismatch between the frozen toolkit binaries the package ships and
# what's actually installed. The Windows SDK's own copies of the same tools
# work correctly since they're matched to the running OS.
#
# Prerequisites:
#   - Windows SDK installed (provides makeappx.exe/signtool.exe)
#   - windows/narraity_signing.pfx present (gitignored -- see
#     README.md's "Installing on Windows" section for how it's generated)
#   - oauth_config.json present at the repo root (see README.md's
#     "Google Drive Sync setup" section)
#
# Usage (Windows PowerShell or PowerShell 7): powershell -File windows\build_msix.ps1

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $repoRoot "build\windows\x64\runner\Release"
$msixPath = Join-Path $releaseDir "narraity.msix"
$pfxPath = Join-Path $repoRoot "windows\narraity_signing.pfx"
$certPassword = "NarraityDevCert2026!"

# Find the newest installed Windows SDK bin folder.
$sdkRoot = "C:\Program Files (x86)\Windows Kits\10\bin"
$sdkVersionDir = Get-ChildItem $sdkRoot -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
    Sort-Object Name -Descending |
    Select-Object -First 1
if (-not $sdkVersionDir) { throw "No Windows SDK bin folder found under $sdkRoot" }
$makeappx = Join-Path $sdkVersionDir.FullName "x64\makeappx.exe"
$signtool = Join-Path $sdkVersionDir.FullName "x64\signtool.exe"

if (-not (Test-Path $pfxPath)) {
    throw "Certificate not found at $pfxPath -- see README.md's Installing on Windows section."
}

Push-Location $repoRoot
try {
    Write-Host "Building unpackaged MSIX files (flutter build windows + manifest)..."
    dart run msix:build --windows-build-args="--dart-define-from-file=oauth_config.json"
    if ($LASTEXITCODE -ne 0) { throw "msix:build failed" }

    if (Test-Path $msixPath) { Remove-Item $msixPath }

    Write-Host "Packing with Windows SDK makeappx.exe..."
    & $makeappx pack /d $releaseDir /p $msixPath /o
    if ($LASTEXITCODE -ne 0) { throw "makeappx pack failed" }

    Write-Host "Signing with Windows SDK signtool.exe..."
    & $signtool sign /fd SHA256 /a /f $pfxPath /p $certPassword $msixPath
    if ($LASTEXITCODE -ne 0) { throw "signtool sign failed" }

    Write-Host "Done: $msixPath"
} finally {
    Pop-Location
}
