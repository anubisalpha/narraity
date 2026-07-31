# Cuts a new Narraity release: bumps the pubspec version/build number *and*
# msix_config's msix_version, runs the test suite as a sanity check, builds +
# signs the MSIX (via build_msix.ps1), generates the .appinstaller manifest
# (via build_appinstaller.ps1), commits + tags, pushes, and publishes a
# GitHub release with the MSIX, its public cert, and the .appinstaller all
# attached. Two things depend on this happening consistently:
#   - The in-app "Check for Updates" feature reads GitHub's "latest release"
#     tag, so a release that skips `gh release create` is invisible to it.
#   - Anyone who installed via the .appinstaller (auto-update path) only
#     ever sees a new version if msix_version actually increased -- Windows
#     compares that 4-part version, not the pubspec/tag semver.
#
# Usage: powershell -File windows\release.ps1 -Version 1.2.0
#        powershell -File windows\release.ps1 -Version 1.2.0 -NotesFile CHANGELOG_fragment.md
#
# Prerequisites:
#   - Clean working tree (commit or stash first)
#   - Everything build_msix.ps1 needs (Windows SDK, windows/narraity_signing.pfx,
#     oauth_config.json)
#   - GitHub CLI (`gh`) installed and authenticated for anubisalpha/narraity

param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$NotesFile
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $repoRoot "pubspec.yaml"

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Version must be plain semver like 1.2.0 (no leading 'v', no +build suffix)."
}

Push-Location $repoRoot
try {
    $status = git status --porcelain
    if ($status) { throw "Working tree is not clean -- commit or stash first:`n$status" }

    # pubspec.yaml is CRLF -- `$` in multiline mode matches before `\n` but
    # leaves a trailing `\r` as part of the line, so a plain `\d+$` fails to
    # match at all. Using a `(?=\r?$)` lookahead instead of consuming `\r?$`
    # means -replace below doesn't eat the `\r` and flip that one line to LF.
    $pubspec = Get-Content $pubspecPath -Raw
    if ($pubspec -notmatch '(?m)^version:\s*\d+\.\d+\.\d+\+(\d+)(?=\r?$)') {
        throw "Could not find a 'version: X.Y.Z+N' line in pubspec.yaml"
    }
    $newBuild = [int]$Matches[1] + 1
    $newVersionLine = "version: $Version+$newBuild"
    $updatedPubspec = $pubspec -replace '(?m)^version:\s*\d+\.\d+\.\d+\+\d+(?=\r?$)', $newVersionLine

    if ($updatedPubspec -notmatch '(?m)^  msix_version:\s*\d+\.\d+\.\d+\.\d+(?=\r?$)') {
        throw "Could not find a '  msix_version: X.Y.Z.W' line under msix_config in pubspec.yaml"
    }
    $newMsixVersionLine = "  msix_version: $Version.0"
    $updatedPubspec = $updatedPubspec -replace '(?m)^  msix_version:\s*\d+\.\d+\.\d+\.\d+(?=\r?$)', $newMsixVersionLine

    Set-Content -Path $pubspecPath -NoNewline -Value $updatedPubspec
    Write-Host "Bumped pubspec.yaml to $newVersionLine / $($newMsixVersionLine.Trim())"

    Write-Host "Running flutter analyze + test as a release sanity check..."
    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed -- fix before releasing" }
    flutter test
    if ($LASTEXITCODE -ne 0) { throw "flutter test failed -- fix before releasing" }

    git add pubspec.yaml
    git commit -m "Release v$Version"
    git tag "v$Version"

    Write-Host "Building signed MSIX..."
    & (Join-Path $PSScriptRoot "build_msix.ps1")

    $msixPath = Join-Path $repoRoot "build\windows\x64\runner\Release\narraity.msix"
    if (-not (Test-Path $msixPath)) { throw "Expected MSIX not found at $msixPath" }

    Write-Host "Generating .appinstaller manifest..."
    & (Join-Path $PSScriptRoot "build_appinstaller.ps1") -Version $Version
    $appInstallerPath = Join-Path $repoRoot "build\windows\x64\runner\Release\narraity.appinstaller"

    $cerPath = Join-Path $repoRoot "windows\narraity_public.cer"
    if (-not (Test-Path $cerPath)) { throw "Expected public certificate not found at $cerPath" }

    Write-Host "Pushing commit and tag..."
    git push origin main
    git push origin "v$Version"

    Write-Host "Creating GitHub release v$Version..."
    $ghArgs = @(
        "release", "create", "v$Version",
        $msixPath, $cerPath, $appInstallerPath,
        "--title", "v$Version"
    )
    if ($NotesFile) { $ghArgs += @("--notes-file", $NotesFile) } else { $ghArgs += "--generate-notes" }
    gh @ghArgs

    Write-Host "Done. Release v$Version published with narraity.msix, narraity_public.cer, and narraity.appinstaller attached."
} finally {
    Pop-Location
}
