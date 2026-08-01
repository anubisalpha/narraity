# Narraity News

Announcements, tips, and roadmap notes — edited directly in this file and pushed to the repo, no
app release required. This is the source for the in-app News Feed (`NewsService`); see
`PLAN.md`'s "News Feed" section for how it's fetched and cached.

Newest entry first. Each entry is a `## YYYY-MM-DD: Title` heading — `NewsService` parses on that
pattern, so keep the format consistent.

## 2026-08-01: Archive & Delete, editable card style, and a new look — v1.2.0

**Archive & Delete for projects.** Previously there was no way to remove a project from your
library short of deleting its folder outside the app. Now every project card has **Archive** and
**Delete** — both compress the whole project into a dated `.zip` and move it out of your library,
restorable any time from the new **Archived & Deleted Projects** screen. Delete works exactly like
Archive (just a separate folder) — Narraity never permanently removes anything on its own; if you
want something truly gone, remove the `.zip` yourself from the file system. Available on projects
in your main library *and* on projects inside a series.

**Card style is now editable after creation.** Novel/Comic/Script was previously locked in at
creation — now it's a "Card style…" option on every project's menu, any time.

**New app icon and header.** Narraity has a new icon (fountain pen + open book), and the library
screen header now shows it beside a styled "Narraity" wordmark, matching the look of the other
`-aity` apps.

**Under the hood:** fixed a bleed-sizing bug and a KDP tag-compliance issue in the print/EPUB
export from the last release; a Google Drive Sync warning was added to Settings for anyone running
the separate Google Drive desktop app alongside Narraity.

## 2026-08-01: Installer changed — no more certificate to trust

Narraity now installs via a plain `narraity-setup.exe` instead of a signed MSIX. If installing a
previous version ever gave you a certificate-trust error, that's gone now — the only thing you'll
see on first run is a one-time Windows "protected your PC" prompt (click "More info" → "Run
anyway"), the same as any unsigned Windows app. Existing installs aren't affected; this only
changes how future versions are installed.

## 2026-08-01: KDP print export (Paperback & Hardcover) — v1.1.0

Two new export formats: **KDP Paperback** and **KDP Hardcover**, producing print-ready interior
PDFs for direct upload to Kindle Direct Publishing. Trim size, bleed, page-count-scaled gutter
margins, roman/Arabic page numbering, alternating running headers, and an auto-generated copyright
page are all handled for you — pick a format, choose a trim size (and, for paperback, an ink/paper
type, since KDP's allowed page-count range depends on both), and export. Cover generation is
explicitly out of scope; use KDP's own Cover Creator for that.

The EPUB export from before is already KDP-eBook-compliant, so there's no separate "KDP eBook"
option — just export as EPUB.

This release also fixes a bleed-sizing bug in the print export (width was doubling KDP's bleed
allowance) and switches footnote reference markers in the EPUB export to a tag confirmed against
KDP's own Kindle Format 8 supported-tag list.

## 2026-08-01: Narraity News launches

This is the first entry in Narraity's new in-app News Feed. From here on, announcements, tips, and
roadmap notes will show up here — check back in-app any time you're online.
