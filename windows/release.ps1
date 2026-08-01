# Cuts a new Narraity release: bumps the pubspec version/build number, runs
# the test suite as a sanity check, builds an unsigned Inno Setup installer
# (via build_installer.ps1), commits + tags, pushes, and publishes a GitHub
# release with narraity-setup.exe attached.
#
# No code-signing certificate involved (see build_installer.ps1's header
# comment and PLAN.md's "Windows packaging" decision for why the earlier
# signed-MSIX approach was dropped) -- the in-app "Check for Updates" feature
# still reads GitHub's "latest release" tag, so a release that skips
# `gh release create` is invisible to it, same as before.
#
# Usage: powershell -File windows\release.ps1 -Version 1.2.0
#        powershell -File windows\release.ps1 -Version 1.2.0 -NotesFile CHANGELOG_fragment.md
#
# Prerequisites:
#   - Clean working tree (commit or stash first)
#   - oauth_config.json present at the repo root
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

    Set-Content -Path $pubspecPath -NoNewline -Value $updatedPubspec
    Write-Host "Bumped pubspec.yaml to $newVersionLine"

    Write-Host "Running flutter analyze + test as a release sanity check..."
    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed -- fix before releasing" }
    flutter test
    if ($LASTEXITCODE -ne 0) { throw "flutter test failed -- fix before releasing" }

    git add pubspec.yaml
    git commit -m "Release v$Version"
    git tag "v$Version"

    Write-Host "Building installer..."
    & (Join-Path $PSScriptRoot "build_installer.ps1") -Version $Version

    $setupPath = Join-Path $repoRoot "build\windows\x64\runner\Release\narraity-setup.exe"
    if (-not (Test-Path $setupPath)) { throw "Expected installer not found at $setupPath" }

    Write-Host "Pushing commit and tag..."
    git push origin main
    git push origin "v$Version"

    Write-Host "Creating GitHub release v$Version..."
    $ghArgs = @(
        "release", "create", "v$Version",
        $setupPath,
        "--title", "v$Version"
    )
    if ($NotesFile) { $ghArgs += @("--notes-file", $NotesFile) } else { $ghArgs += "--generate-notes" }
    gh @ghArgs

    Write-Host "Done. Release v$Version published with narraity-setup.exe attached."
} finally {
    Pop-Location
}
