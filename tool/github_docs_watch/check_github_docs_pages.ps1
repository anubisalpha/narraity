<#
.SYNOPSIS
  Fetches GitHub's own API/OAuth docs pages that Narraity's code depends on, diffs each against
  its last saved snapshot, and files a GitHub issue if anything changed. Pure fetch+diff+issue -
  no LLM judgment involved anywhere in the pipeline, including the "flag it" step.

.DESCRIPTION
  Sibling to `tool/kdp_watch/check_kdp_pages.ps1` (same design, deliberately not merged into it -
  that watcher's issue title/label/doc comments are specifically about KDP formatting rules, and
  mixing in unrelated GitHub docs pages would make its issues confusing). This one exists because
  a real bug shipped in `lib/services/github_auth_service.dart`'s Device Flow implementation (the
  `grant_type` value didn't match GitHub's documented one - see BUILD_LOG.md, found and fixed
  2026-08-02 during Phase 8's live smoke test) that a stale mental model of GitHub's docs directly
  caused. Watching the source docs page catches the next silent change GitHub makes to this API
  before it causes the same kind of failure again.

  Snapshots are stored as one .txt file per page (HTML tags stripped, whitespace normalized) in
  this script's own directory. First run for a given page just saves a baseline snapshot with no
  diff output. Every subsequent run compares the freshly fetched page to the saved snapshot; if
  the normalized text differs, the old and new snapshots are both kept (old renamed with a
  timestamp), a line-level diff is printed, and one GitHub issue covering every changed page for
  this run is filed via `gh issue create` (repo below). If nothing changed, the script exits
  quietly with a one-line summary and files nothing.

.NOTES
  Text-only normalized diff, not a pixel/DOM diff - cosmetic HTML/markup changes with no visible
  text change won't be flagged, but nav/boilerplate churn on GitHub's side could still produce
  noise. If that happens in practice, tighten Get-NormalizedText's stripping rules rather than
  reaching for an LLM to eyeball it.

  Requires `gh` authenticated (already set up for this machine - see
  claudecore/memory/github_ssh_setup.md) with access to $GitHubRepo.
#>

$ErrorActionPreference = 'Stop'

$GitHubRepo = 'anubisalpha/narraity'

$pages = @(
    @{ Name = 'oauth-device-flow'; Url = 'https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps' }
)

$scriptDir = $PSScriptRoot

function Get-NormalizedText {
    param([string]$Html)

    # Drop script/style blocks entirely, then strip all remaining tags.
    $text = $Html -replace '(?is)<script.*?</script>', ''
    $text = $text -replace '(?is)<style.*?</style>', ''
    $text = $text -replace '(?is)<!--.*?-->', ''
    $text = $text -replace '(?is)<[^>]+>', "`n"

    # Decode the handful of entities docs.github.com actually uses.
    $text = $text -replace '&nbsp;', ' ' -replace '&amp;', '&' -replace '&quot;', '"' `
                  -replace '&#39;', "'" -replace '&lsquo;', "'" -replace '&rsquo;', "'" `
                  -replace '&ldquo;', '"' -replace '&rdquo;', '"' -replace '&mdash;', '-'

    # Collapse whitespace so incidental formatting changes don't register as diffs.
    $lines = $text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    return ($lines -join "`n")
}

$changedPages = @()
$newPages = @()
$issueBodyParts = @()

foreach ($page in $pages) {
    $snapshotPath = Join-Path $scriptDir "$($page.Name).txt"
    Write-Host "Fetching $($page.Name) ($($page.Url)) ..."

    try {
        $response = Invoke-WebRequest -Uri $page.Url -UseBasicParsing -TimeoutSec 30
    } catch {
        Write-Warning "  Failed to fetch $($page.Name): $_"
        continue
    }

    $current = Get-NormalizedText -Html $response.Content

    if (-not (Test-Path $snapshotPath)) {
        Set-Content -Path $snapshotPath -Value $current -Encoding utf8
        $newPages += $page.Name
        Write-Host "  No prior snapshot - baseline saved."
        continue
    }

    $previous = (Get-Content -Path $snapshotPath -Raw -Encoding utf8).TrimEnd("`r", "`n")
    if ($previous -eq $current) {
        Write-Host "  No change."
        continue
    }

    # Something changed - keep the old snapshot (timestamped) and report a line-level diff.
    $timestamp = Get-Date -Format 'yyyy-MM-dd'
    $archivePath = Join-Path $scriptDir "$($page.Name).$timestamp.prev.txt"
    Copy-Item -Path $snapshotPath -Destination $archivePath -Force

    $prevLines = $previous -split "`n"
    $currLines = $current -split "`n"
    $diff = Compare-Object -ReferenceObject $prevLines -DifferenceObject $currLines

    Write-Host "  CHANGED - see diff below. Old snapshot archived to $archivePath"
    $diffLines = @()
    $diff | ForEach-Object {
        $marker = if ($_.SideIndicator -eq '=>') { '+' } else { '-' }
        $line = "    $marker $($_.InputObject)"
        Write-Host $line
        $diffLines += $line
    }

    $issueBodyParts += "### $($page.Name)`n$($page.Url)`n`n``````diff`n$($diffLines -join "`n")`n```````n"

    Set-Content -Path $snapshotPath -Value $current -Encoding utf8
    $changedPages += $page.Name
}

Write-Host ''
if ($changedPages.Count -gt 0) {
    Write-Host "SUMMARY: changed pages: $($changedPages -join ', ')" -ForegroundColor Yellow

    $issueTitle = "GitHub API docs pages changed: $($changedPages -join ', ') ($(Get-Date -Format 'yyyy-MM-dd'))"
    $tick = [char]96
    $issueBody = "Automated check (${tick}tool/github_docs_watch/check_github_docs_pages.ps1${tick}) detected changes on the following GitHub docs pages, which Narraity's OAuth/API integrations (Feedback's Device Flow sign-in, Release Notes/News Feed) depend on:`n`n" + ($issueBodyParts -join "`n")
    $bodyFile = Join-Path $scriptDir '.issue-body.tmp.md'
    Set-Content -Path $bodyFile -Value $issueBody -Encoding utf8

    try {
        & gh issue create --repo $GitHubRepo --title $issueTitle --body-file $bodyFile --label 'github-docs-watch' 2>&1 | Write-Host
        Write-Host "GitHub issue filed on $GitHubRepo."
    } catch {
        Write-Warning "Failed to create GitHub issue: $_"
        Write-Warning "Diff content preserved above and in the archived .prev.txt snapshots - file the issue manually if needed."
    } finally {
        Remove-Item -Path $bodyFile -Force -ErrorAction SilentlyContinue
    }
} elseif ($newPages.Count -gt 0) {
    Write-Host "SUMMARY: baseline snapshots saved for: $($newPages -join ', '). Nothing to compare yet - next run will diff against these."
} else {
    Write-Host "SUMMARY: no changes detected on any page."
}
