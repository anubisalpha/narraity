# Narraity

[![CI](https://github.com/anubisalpha/narraity/actions/workflows/ci.yml/badge.svg)](https://github.com/anubisalpha/narraity/actions/workflows/ci.yml)

A local-first novel writing app built with Flutter, for writers who want to own their manuscript
files, skip the subscription, and get more real writing tools than a blank page.

Built as an alternative to Dabble: same core workflow, no cloud lock-in, no monthly fee, and a
handful of features Dabble doesn't have (below).

## Download

Windows installer builds (`.msix`) are published on the [Releases page](../../releases). See
["Installing on Windows"](#installing-on-windows) below for the one-time certificate-trust step a
self-signed package needs.

No Android build is published yet.

## License

All rights reserved. This repository is public so the code and its history are visible, but no
license is granted to use, copy, modify, or redistribute it.

## Why this exists

- **You own the files.** Every project is plain JSON + Markdown on your own disk — human-readable,
  diffable, recoverable without the app. No proprietary format, no vendor lock-in.
- **No subscription.** One-time build, sync uses your own free Google Drive quota instead of a
  paid backend.
- **Offline-first.** Writing, dictation, and history all work with no internet connection.

## Platforms

v1 targets **Windows desktop and Android**. macOS, iOS, and Linux are architected for (the stack
is portable) but not built or shipped yet — see the Cross-Platform Roadmap in `PLAN.md` for the
full breakdown and what changes per platform when that day comes.

## Features

### Project & library management
- Local, file-based project library (`Documents/Narraity/`) — create, open, browse projects
- **Series**: group related projects (e.g. a trilogy) under a named series, shown as a stacked card
  on the library screen; open it to see and manage every book inside
- **Front cover images** — set one per project from the manuscript tree's front-matter area; shows
  as a thumbnail on that project's (or its series') library card
- **Drag-and-drop reordering** on the library screen and inside a series, independent of each
  project's own recency-based default ordering
- Dark / light / system theme
- Settings screen with a side-nav structure ready to grow (Appearance, Editor, Dictation, Read
  Aloud, Backup & Vault, Google Drive Sync now; Spell Check's language picker and Export slotted
  in as later phases land)

### Global Ideas
- Quick-capture space for ideas outside any single project, reachable from anywhere in the app
- Search and tag filtering
- Promote an idea straight into a new project, or attach it as a story note on an existing one —
  ideas are marked "used," never deleted, so the origin trail stays intact

### Manuscript editor
- Act → Chapter → Scene tree with drag-to-reorder scenes, add/delete at every level
- Prologue / Epilogue / Dedication / Author's Note as first-class front/back matter
- Debounced autosaving Markdown editor (title + front-matter + prose per scene)
- Formatting toolbar (bold, italic, strikethrough, scene break, block quote, heading)
- Undo/redo, Find & Replace, live word count
- Focus Mode — hides all chrome, Esc to exit
- Adjustable writing font, size, and line spacing (separate from export formatting)
- Per-project to-do list, optionally linked to a scene

### Characters, worldbuilding & story notes
- **Character profiles** with author-defined fields — a starter template (Role, Age, Appearance,
  Personality, Goals, Backstory, Notes) that can be renamed, removed, reordered, or added to, because
  no fixed character sheet suits every writer
- **Worldbuilding entries** grouped by a freeform category (Location, Faction, Magic, or anything you
  type) — the sidebar builds its groups from the categories actually in use
- Any field can be starred as **quick reference**, marking what's worth seeing at a glance while
  writing (consumed by the Reference Panel)
- Optional image per character/entry, copied into the project so it stays self-contained and portable
- **Story Notes** with folders *and* tags: file notes into folders, tag them freely, and search across
  every note's title, body, and tags — extra words narrow the search, and title/tag hits rank above
  passing mentions in a body
- Deleting a folder moves its notes back to the top level rather than deleting them
- Notes promoted from Global Ideas appear here automatically, marked with their origin

### Reference Panel
- Dockable, resizable, collapsible panel on the right of the editor — reference material **while you
  write**, never a navigation away from the manuscript
- Type `@` in a scene to get an autocomplete of your characters and world entries (↑↓ to choose, Enter
  to insert, Esc to dismiss); it inserts a readable wiki-style `[[Elena Vance]]` mention
- The panel automatically shows a card for everything the open scene mentions, plus anything you've
  **pinned** to keep visible regardless of scene
- Cards show only the fields you starred as quick reference, and any of them can be **edited inline**
  without leaving the editor
- A mention with no matching profile shows as an unresolved card with a one-click "Create" — useful
  when a character turns up in the prose before they have a profile
- Panel visibility, width, and pins persist between sessions (per project for pins)

### Plot Grid
- Colour-coded **plotlines** (main plot, subplots, POV arcs) as rows, manuscript **scenes** in
  document order as columns — a spreadsheet-style view of what's happening where
- Tap a cell to add or edit a plot point (title + notes); an empty cell is a single tap away from a
  new beat, no separate "add" flow
- Add/rename/recolour/delete plotlines from the grid itself; deleting a plotline removes every point
  on it
- Opens full-screen (like Goals) from its own toolbar icon, since a grid needs real width rather than
  a 280px sidebar slot

### Timeline
- In-story chronology, distinct from the Plot Grid (structural, manuscript order) — tracks **when
  things happen**, not where they sit in the manuscript
- Multiple parallel **tracks** ("Main", "Backstory", a POV character's arc, ...) as freely
  **reorderable rows** on a shared canvas, each toggleable so you can overlay or isolate whichever
  ones matter right now
- Event cards are **freely draggable in both directions** — horizontally for time, vertically to
  stagger cards that are close together so they don't overlap — rather than only nudging along a
  fixed left-to-right order. A thin baseline line marks each track's row; there's no visible grid,
  it's just an alignment guide
- Each card shows a **connector line back to its own track's baseline**, so a staggered card's home
  track is never ambiguous. Drag a card onto a different track's row and it reassigns there —
  releasing past the midpoint between two tracks snaps the card (and its connector) to the nearer one,
  previewed live while you drag
- Events carry a freeform "when" (a real date, "Day 3", "Spring, Year 1" — whatever fits the story's
  own sense of time) plus notes, and can link to scenes, characters, and world entries
- A linked scene shows as a chip on the event card — tap it to jump straight to that scene in the
  manuscript editor
- Track management (reorder, show/hide, add event, delete) lives in a side list next to the canvas

### Family Tree / Relationship Diagram
- Pan/zoomable canvas of your characters (pulled live from Character Profiles) with draggable
  positions that persist between sessions and track the cursor precisely at any zoom level
- **New Character** button right on this screen — mapping relationships is exactly when you notice
  someone's missing, no need to switch back to the Characters tab
- Relationships (family, romantic, friend, rival, ally, mentor, other, plus a custom label) drawn as
  **colour-coded lines** — same colour for the line, the badge outline, the side-list dot, and the
  Type dropdown, so one glance tells you what kind of relationship it is anywhere in the screen
- The label renders as a **badge** (filled, rounded, sitting on top of the line) rather than raw text,
  so it stays legible wherever a line crosses under it
- **Drag one character's node onto another** to open the relationship dialog pre-filled with the
  dragged character and the one it landed on — editing the existing relationship between them if
  there already is one. The dragged node snaps back to its own position afterward; this gesture
  links, it doesn't move. Lines follow the node live while dragging
- Add relationships via the "+" picker instead (pick both characters, a type, an optional label) when
  drag-and-drop isn't convenient; manage existing ones from a side list

### Comments, highlights & sticky notes
- Select text in the editor to add a highlight (4-swatch picker), a comment, or a sticky note — all
  three (plus footnotes) anchor to that exact span, painted as background tints directly in the
  plain-text editor
- A footnote anchors to the caret itself rather than a selection
- If the surrounding prose gets edited later, an anchored range self-heals if its text just moved
  elsewhere in the scene; if the text is genuinely gone, it's flagged rather than silently misplaced
- An Annotations panel lists everything on the current scene — jump to any one, mark a comment
  resolved, or delete it

### AI/external review round-trip
- **Export for Review**, reachable from the project's top app bar: pick any set of scenes via a
  checklist, and get one Markdown file with a stable anchor id before every paragraph — readable by
  any human reviewer or pasted straight into an LLM
- The file leads with a metadata header (project title, subtitle, author, export date) so whoever
  opens it knows whose work they're looking at
- **Import Review Comments** reads a reviewer's JSON reply back in and re-attaches each comment to
  the exact right spot, using the same self-healing anchor mechanism as in-editor comments
- **Reviewing tool**, reachable from the Library screen itself — no project or account needed. A
  3rd-party reviewer opens the exported file, comments paragraph-by-paragraph, and exports their
  comments to send back. Every review session persists so it survives closing the app

### Read Aloud (text-to-speech)
- Reads from wherever your cursor is (or the start of the scene if nothing's placed) using the
  OS's own speech engine — Windows WinRT voices, Android `TextToSpeech` — no download needed
- The word currently being spoken highlights live in the text as it's read
- Voice, speed, and pitch controls in Settings, remembered between sessions
- Stops cleanly if you start typing (a real edit would otherwise leave the reading position
  pointing at stale text) or switch scenes

### Spell check (offline)
- Real Hunspell under the hood (the same engine LibreOffice/Firefox/Chrome use), via a hand-written
  FFI binding — no Dart/Flutter package for this exists, so `libhunspell.dll` is built from source
  and vendored the same way as the Vosk dictation engine
- **en-GB (UK English) as the default**, bundled with the app — no download needed
- Misspelled words get a red wavy underline right in the editor
- A Spelling panel (badge shows the count) lists every flagged word with suggestion chips — tap one
  to replace it in place — and an "add to dictionary" action for names and words that are correct
  but not in the wordlist
- Multi-language/variant support (US/CA/AU/NZ/ZA English, other languages) is planned but not built
  yet

### Thesaurus & dictionary (offline)
- Bundled Open English WordNet (CC BY 4.0) queried via `sqlite3` — synonyms and definitions, no
  network dependency, instant lookups
- Select a single word and right-click (or use the selection toolbar on Android) for a "Look Up"
  entry — opens a popover with every WordNet sense: part of speech, definition, and synonym chips
  you can tap to replace the word in place
- Hypernym/hyponym (broader/narrower term) browsing is planned but not built yet

### Voice dictation (offline)
- Windows: a hand-written Dart FFI binding straight to the real Vosk engine (`libvosk.dll`,
  vendored — see "Why not a Vosk plugin?" below)
- Android: native on-device `SpeechRecognizer`, auto-restarted across the OS's silence timeout to
  approximate continuous dictation
- Spoken punctuation commands: "comma," "full stop"/"period," "question mark," "exclamation
  mark/point," "new line," "new paragraph"
- Language + accuracy picker (English UK/US, Small ~40MB / Large ~124–281MB depending on
  language), resolved against Vosk's *live* model catalog rather than a hardcoded version
- Full model management in Settings: download, re-download, delete, see what's on disk

### Adaptive Goal Engine
- Goals scoped to a whole project, a single act, or a single scene
- **App-wide goals too** — track a target across every project, or just the ones you pick
- Daily word-count target recalculates automatically from your *actual* progress: miss a day and
  tomorrow's target rises to compensate; get ahead and it eases off — no separate "redistribute"
  step, it falls straight out of recomputing `remaining words ÷ remaining working days` fresh
  every day
- Working calendar: mark recurring days off (e.g. weekends)
- Starting word count auto-detected from the existing manuscript, so goals never double-count
- Progress rings (today vs. overall), a 30-day activity heatmap, goal setup wizard with a live
  preview of the resulting daily target

### Version History
- Automatic snapshots on save (after ~30s idle or ~300 words changed, whichever comes first),
  scoped per scene
- Named checkpoints ("Save Checkpoint") that are never pruned
- Snapshots are stored as diffs against the previous version (via `diff_match_patch`), not full
  copies — the history stays lightweight even over a long project
- Pruning policy thins old auto-snapshots over time (all of the last 48h kept, then hourly → daily
  → weekly) while preserving the ability to reconstruct any surviving point exactly, and *never*
  prunes the single most recent snapshot or any checkpoint
- Per-scene History screen: timeline, word-count sparkline, diff view between any two points,
  one-click restore — restoring creates a *new* history entry rather than overwriting, so the
  restore itself is undoable

### Data protection
- Every history snapshot is HMAC-signed and chained to the one before it, so an edited, deleted, or
  reordered snapshot file is detected on read (not just trusted) and quarantined rather than
  silently replayed — catches both deliberate tampering and ordinary corruption (a flipped byte
  breaks the signature check either way)
- A `.history_backup/` mirror of every snapshot enables auto-repair: a corrupted primary file is
  restored in place from its backup copy if the backup still verifies clean
- The signing key is derived from a user password (Argon2id) rather than OS-specific secure
  storage — pure Dart, no native platform dependency, and the same key on every device once Drive
  sync exists, avoiding a false-tamper mismatch a device-local key would cause
- Optional password-protected **Vault**: a single encrypted (AES-256-GCM) archive of the whole
  project, independent of the many small live files, for disaster recovery — kept in rotating
  generations (default 10) so one bad refresh can't destroy the last good backup
- **Settings → Backup & Vault** covers the whole lifecycle: set the password, unlock, adjust how many
  generations to keep, back up any project on demand, restore a chosen generation, change the password
- Backups refresh automatically while a project is open (every 30 minutes) and once when it's closed
- Opening a project with a locked vault offers a **skippable** unlock prompt — declining keeps
  writing working normally, it just leaves new history unsigned until you unlock from Settings
- Restoring never overwrites: a generation is unpacked into a new project folder beside the original,
  so you compare the two and decide which to keep
- Changing the password re-signs every snapshot in every project first, and only then switches the
  stored password — so a failure part-way through can't leave history it can no longer verify.
  Vault files made before the change still open with the old password

### Google Drive Sync
- Offline-first: every save is already local and immediate — sync is best-effort, never on the
  write path itself
- Sign in with your own Google account (`drive.file` scope only — the app can only see files and
  folders it creates itself, never your whole Drive)
- One dedicated `Narraity/` folder on your Drive, mirroring your local project structure exactly
- A three-way diff (local vs. Drive vs. the last-known-synced state) decides what to push, pull, or
  leave alone per file — same approach any offline-first sync tool (Dropbox, git) uses
- A deletion racing an edit resolves itself automatically, keeping whichever side still has content
  — no reason to ask you to choose when there's only one sensible answer
- Genuine conflicts (edited differently on this device *and* on Drive) go to a dedicated **Sync
  Conflicts** screen: keep this device's version, keep Drive's, or keep both (your version is saved
  aside, never silently discarded)
- **Settings → Google Drive Sync**: connect/disconnect, and a manual "Sync now" (with a
  last-synced timestamp) for every project, **plus your Vault backups and your app settings** —
  not just manuscripts
- OAuth via the system browser (a "Desktop app" client type + local-loopback redirect) rather than
  the `google_sign_in` package — that package doesn't support Windows

Two sync targets beyond your projects, always present once connected (no extra toggle needed):
- **Vault backups** — without this, the encrypted Vault (disaster-recovery archives, see below)
  never left the device at all, which quietly defeated its own purpose. Now it syncs the same way
  a project does.
- **App settings** — theme, dictation language/accuracy preference, spell check on/off, Read Aloud
  voice/rate/pitch, editor font, Vault retention settings, and the auto-sync toggles below all
  travel to a new device in one consolidated file. (Reference Panel layout state and pins
  deliberately don't — they're per-machine workspace state, not app options.)

**Automatic sync**, all off by default — turn on whichever combination fits:
- **Sync immediately after saving** — watches the currently open project and syncs just the one
  file that changed, moments after it saves, without a full project re-check
- **Daily sync** — a guaranteed full sync + reconciliation check at least once a day
- **More frequent sync** — an additional full sync on a shorter interval you choose (5/15/30/60 min)
- **Sync Log** (Settings → Google Drive Sync → Sync Log) — every sync attempt, manual or automatic,
  recorded with what it did or what went wrong, so "is this actually syncing?" has a real answer

### Export
- **PDF** — full formatting, headings, page layout; every top-level section (front/back matter,
  and any Book/Act/Chapter/Part-labelled node regardless of nesting depth) starts on its own page
- **Word document (.docx)** — full formatting, editable in Word, with the same page-break rule as PDF
- **EPUB** — reflowable e-book with a table of contents, readable on Kindle/e-readers; ships its own
  stylesheet (indented paragraphs, centered chapter headings) instead of relying on reader defaults
- **Per-section title control** — right-click any section in the manuscript tree to toggle whether
  its title prints in exports at all (e.g. hide an imported book's redundant "Book 1" heading)
- **Plain text (.txt)** — an explicit stripped-down option; the app warns that formatting and images
  are dropped before it exports one
- Reachable from the project toolbar's Export icon — pick a format, choose where to save, done
- KDP-specific print formatting (trim size, margins, bleed, a separate wraparound cover) isn't built
  yet — this is general-purpose export, not the print-ready path

## Tech stack

- **Flutter** + **Riverpod** for state
- **Local file storage** — JSON + Markdown, no embedded database
- **`diff_match_patch`** for Version History's diff/patch storage
- **`crypto`** + **`cryptography`** (HMAC-SHA256, Argon2id, AES-256-GCM) for history tamper-evidence
  and the password-protected Vault — no native platform dependency, works identically on every OS
- **`record`** (cross-platform mic capture) + a hand-written FFI binding for Windows dictation
- **`speech_to_text`** for Android dictation
- **`file_picker`** for choosing character/worldbuilding images and export save locations
- **`pdf`** for PDF export; DOCX and EPUB are hand-rolled directly via **`archive`** (no mature
  pure-Dart writer exists for either format)
- No servers, no accounts, no telemetry — everything above runs entirely on-device

## Installing on Windows

Every release publishes the same package two ways — pick whichever fits:

- **Manual install** — download the `.msix` yourself, install it, and use **Check for Updates**
  (Settings → About) whenever you want to see if a newer version exists. You're in control of
  exactly when anything changes.
- **Install with auto-updates** — install once via the `.appinstaller` link below; from then on,
  Windows itself checks for a newer version on every launch and asks you to accept it (never
  silent). Nothing extra to remember.

Both paths need the same one-time certificate trust, since the package is signed with a
**self-signed development certificate**, not one from a trusted certificate authority (getting one
of those is a paid, verified purchase — not something scripted here).

### Option A: Manual install

1. Download both `narraity.msix` and `narraity_public.cer` from the [Releases page](../../releases).
2. Double-click `narraity_public.cer` → **Install Certificate** → **Local Machine** (needs admin) →
   **Place all certificates in the following store** → **Trusted People** → Finish.
3. Double-click `narraity.msix` to install the app.

### Option B: Install with auto-updates

1. Download `narraity_public.cer` from the [Releases page](../../releases) and trust it as in step 2
   above (one-time, same as the manual path).
2. Download and double-click
   [`narraity.appinstaller`](https://github.com/anubisalpha/narraity/releases/latest/download/narraity.appinstaller) —
   **use that exact link**, not a version-pinned release URL, so future update checks keep
   resolving to whatever's newest rather than freezing at today's version.
3. Windows installs the app and remembers where it came from. On each future launch, if a newer
   version has been published, Windows prompts you to accept the update before it applies it.

Either way, this is a one-time step per machine. If a CA-issued certificate replaces the
self-signed one later, the trust step won't be needed at all.

## Building from source / contributing

See [`DEVELOPMENT.md`](DEVELOPMENT.md).
