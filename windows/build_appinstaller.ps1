# Generates narraity.appinstaller -- the manifest that lets Windows'
# built-in App Installer auto-update a sideloaded (non-Store) MSIX. Windows
# re-fetches this exact file from the URL the user *originally* installed it
# from, so both this file and the .msix it points to must be published at
# stable "latest" URLs every release -- see release.ps1 and README.md's
# "Installing on Windows (with auto-updates)" section. A version-pinned
# release URL would freeze auto-update at that one release forever.
#
# Usage: powershell -File windows\build_appinstaller.ps1 -Version 1.2.0
# (called by release.ps1 -- not normally run by hand)

param(
    [Parameter(Mandatory = $true)]
    [string]$Version
)

$ErrorActionPreference = "Stop"

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Version must be plain semver like 1.2.0 (no leading 'v', no +build suffix)."
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $repoRoot "build\windows\x64\runner\Release"
$outputPath = Join-Path $releaseDir "narraity.appinstaller"

# Must match pubspec.yaml's msix_config: identity_name and the signing
# certificate's Subject (see DEVELOPMENT.md's MSIX section).
$identityName = "com.anubisproductions.narraity"
$publisher = "CN=Anubis Productions"
$msixVersion = "$Version.0"

# GitHub's "latest" release alias -- resolves to whatever release is newest,
# so it stays correct without editing this file's URLs by hand each time.
$baseUrl = "https://github.com/anubisalpha/narraity/releases/latest/download"

$xml = @"
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller
    Uri="$baseUrl/narraity.appinstaller"
    Version="$msixVersion"
    xmlns="http://schemas.microsoft.com/appx/appinstaller/2018">

  <MainPackage
      Name="$identityName"
      Publisher="$publisher"
      Version="$msixVersion"
      ProcessorArchitecture="x64"
      Uri="$baseUrl/narraity.msix" />

  <UpdateSettings>
    <!-- ShowPrompt="true": the user is notified and accepts the update
         rather than it installing silently in the background, a deliberate
         choice for a self-signed, early-stage app. HoursBetweenUpdateChecks
         set to "0" checks on every launch (still just a check, not an
         install, without ShowPrompt being accepted). -->
    <OnLaunch HoursBetweenUpdateChecks="0" ShowPrompt="true" UpdateBlocksActivation="false" />
  </UpdateSettings>
</AppInstaller>
"@

if (-not (Test-Path $releaseDir)) {
    throw "Release dir not found at $releaseDir -- build the MSIX first."
}

Set-Content -Path $outputPath -Value $xml -Encoding UTF8
Write-Host "Wrote $outputPath"
