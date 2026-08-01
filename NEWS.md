# Narraity News

Announcements, tips, and roadmap notes — edited directly in this file and pushed to the repo, no
app release required. This is the source for the in-app News Feed (`NewsService`); see
`PLAN.md`'s "News Feed" section for how it's fetched and cached.

Newest entry first. Each entry is a `## YYYY-MM-DD: Title` heading — `NewsService` parses on that
pattern, so keep the format consistent.

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
