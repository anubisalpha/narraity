# Narraity News

Announcements, tips, and roadmap notes — edited directly in this file and pushed to the repo, no
app release required. This is the source for the in-app News Feed (`NewsService`); see
`PLAN.md`'s "News Feed" section for how it's fetched and cached.

Newest entry first. Each entry is a `## YYYY-MM-DD: Title` heading — `NewsService` parses on that
pattern, so keep the format consistent.

## 2026-08-02: Series-level content, a real Help system — v1.4.0

**Characters, World, Notes, and To-dos can now live at the series level**, shared across every
book in a series instead of being copied into each one separately. Open a series from the Library
and its own Characters/World/Notes/To-dos tabs work exactly like a project's — a recurring
antagonist or the shared magic system only needs to exist once. Any project-level character or
world entry can be **moved** to its series (or back into a specific project) from its own menu,
keeping its fields and image intact.

**The Reference Panel gained a Series tab.** Pin a character or world entry from a series' own
tabs and it shows up in the "Series" tab of every project's Reference Panel inside that series,
right alongside the existing "Project" tab for that book's own pins — kept deliberately separate
so the two never blur together.

**A real Help system.** Settings has a new **Help** category: every icon and panel in the app,
explained, organized into collapsible segments with a search box. And every major screen — Library,
a Series, an open project's toolbar, Goals, Plot Grid, Timeline, Relationships, and both Export
screens — now has its own **?** icon in the top-right corner that slides out a panel explaining
just that page, with a link through to the full Help page if you want to browse further.

**Smaller fixes:** the back button from a project that's part of a series now returns you to that
series' screen instead of always landing on the Library. Google Drive Sync gained a **Sync All
Now** button. The Backup Vault can now run **without a password** if you'd rather trade the
encryption for convenience — a toggle in Settings > Backup & Vault, reflected honestly in the
status bar (an orange icon, not a green one, when backups are running unencrypted). The status bar
itself now stays visible everywhere, including Focus Mode and the series screen, instead of
disappearing on some pages.

## 2026-08-02: Rename projects, a resizable sidebar, and a status bar — v1.3.0

**Projects can now be renamed.** Tap the pencil next to the title in a project's toolbar to give it
a proper name any time — no longer locked in from creation.

**The left sidebar (manuscript tree / characters / world / notes / to-dos) is now resizable.** Drag
the divider to the width you want; it's remembered as a proportion of the window, so it stays
sensible whether you're on a laptop screen or an ultrawide monitor, and across resizes.

**A new status bar** sits along the bottom of the app: version and copyright on the left, and on the
right, at-a-glance icons for Spell check, Thesaurus, the Backup Vault, and Google Drive — hover any
of them for details (the Vault icon tells you plainly whether your backups are actually encrypted
right now; the Drive icon flickers while a sync is in progress). Hidden in Focus Mode along with the
rest of the chrome.

**Global Ideas now asks before deleting** an idea, matching every other delete confirmation in the
app — previously it removed the idea immediately with no way back.

**Under the hood:** fixed a real freeze — spell check's first run on a scene (or its very first run
of a session, when the dictionary itself has to load) used to block the UI thread, which could look
like the app had hung on any page with a lot of misspellings. It now runs off the critical path with
a "Checking spelling…" indicator instead. Also fixed a related case where opening a project could
sit on a loading spinner far longer than it should before showing your first scene.

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
