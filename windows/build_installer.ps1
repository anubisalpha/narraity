# Builds Narraity's Windows installer: `flutter build windows` followed by
# Inno Setup compiling windows/narraity_installer.iss into narraity-setup.exe.
#
# Deliberately unsigned -- see PLAN.md's "Windows packaging" decision and
# DEVELOPMENT.md's "Building the Windows installer" section for why the
# earlier signed-MSIX pipeline was dropped.
#
# Prerequisites:
#   - Inno Setup installed (`choco install innosetup` or jrsoftware.org)
#   - oauth_config.json present at the repo root
#
# Usage (Windows PowerShell or PowerShell 7): powershell -File windows\build_installer.ps1

param(
    # Stamped into the installer's AppVersion / "Add or Remove Programs" entry.
    # Defaults to pubspec.yaml's version if not passed explicitly.
    [string]$Version
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$issPath = Join-Path $PSScriptRoot "narraity_installer.iss"
$releaseDir = Join-Path $repoRoot "build\windows\x64\runner\Release"

if (-not $Version) {
    $pubspec = Get-Content (Join-Path $repoRoot "pubspec.yaml") -Raw
    if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)') {
        throw "Could not find a 'version: X.Y.Z' line in pubspec.yaml -- pass -Version explicitly"
    }
    $Version = $Matches[1]
}

# Find ISCC.exe (Inno Setup's compiler) -- not reliably on PATH after a
# Chocolatey install, so check the two standard install locations too.
$iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if (-not $iscc) {
    $candidates = @(
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe"
    )
    $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $found) {
        throw "ISCC.exe (Inno Setup's compiler) not found -- install it with 'choco install innosetup' or from jrsoftware.org"
    }
    $iscc = $found
} else {
    $iscc = $iscc.Source
}

Push-Location $repoRoot
try {
    Write-Host "Building Windows release (flutter build windows)..."
    flutter build windows --dart-define-from-file=oauth_config.json
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }

    $setupPath = Join-Path $releaseDir "narraity-setup.exe"
    if (Test-Path $setupPath) { Remove-Item $setupPath }

    Write-Host "Compiling installer with Inno Setup ($Version)..."
    & $iscc "/DAppVersion=$Version" $issPath
    if ($LASTEXITCODE -ne 0) { throw "ISCC.exe failed" }

    if (-not (Test-Path $setupPath)) { throw "Expected installer not found at $setupPath" }
    Write-Host "Done: $setupPath"
} finally {
    Pop-Location
}
