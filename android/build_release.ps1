# Builds Narraity's signed Android release artifacts (AAB for Play Store,
# APK for direct/beta install) with the Google Drive OAuth client wired in.
#
# This exists because `flutter build appbundle --release` /
# `flutter build apk --release` on their own do NOT pick up oauth_config.json
# automatically -- every prior Android build (including the one submitted for
# testing) was built without `--dart-define-from-file`, so Google Drive Sync
# silently reported "not configured" despite working fine on Windows (see
# windows/build_installer.ps1 / windows/release.ps1, which already did this
# correctly). Always build Android releases through this script, not a bare
# `flutter build` command, so that gap can't reoccur.
#
# Prerequisites:
#   - oauth_config.json present at the repo root
#   - keystore.properties + the release .jks present at the repo root
#     (see PLAY_STORE_PUBLISHING.md's "App Signing" section) -- without these,
#     android/app/build.gradle.kts falls back to debug signing
#
# Usage: powershell -File android\build_release.ps1
#        powershell -File android\build_release.ps1 -ApkOnly   # skip the AAB
#        powershell -File android\build_release.ps1 -AabOnly   # skip the APK

param(
    [switch]$ApkOnly,
    [switch]$AabOnly
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$oauthConfigPath = Join-Path $repoRoot "oauth_config.json"
$keystorePropsPath = Join-Path $repoRoot "keystore.properties"

Push-Location $repoRoot
try {
    if (-not (Test-Path $oauthConfigPath)) {
        throw "oauth_config.json not found at repo root -- Google Drive Sync would silently " +
              "build as 'not configured'. Copy oauth_config.example.json and fill in real values."
    }
    if (-not (Test-Path $keystorePropsPath)) {
        Write-Warning "keystore.properties not found -- build.gradle.kts will fall back to debug " +
                       "signing, producing an unsigned-for-release artifact."
    }

    if (-not $ApkOnly) {
        Write-Host "Building Android App Bundle (release, with oauth_config.json)..."
        flutter build appbundle --release --dart-define-from-file=oauth_config.json
        if ($LASTEXITCODE -ne 0) { throw "flutter build appbundle failed" }
        Write-Host "Done: build\app\outputs\bundle\release\app-release.aab"
    }

    if (-not $AabOnly) {
        Write-Host "Building Android APK (release, with oauth_config.json)..."
        flutter build apk --release --dart-define-from-file=oauth_config.json
        if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }
        Write-Host "Done: build\app\outputs\flutter-apk\app-release.apk"
    }
} finally {
    Pop-Location
}
