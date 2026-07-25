# Narraity

A local-first novel writing app built with Flutter, for writers who want to own their manuscript
files, skip the subscription, and get more real writing tools than a blank page.

Built as an alternative to Dabble: same core workflow, no cloud lock-in, no monthly fee, and a
handful of features Dabble doesn't have (below).

## Why this exists

- **You own the files.** Every project is plain JSON + Markdown on your own disk — human-readable,
  diffable, recoverable without the app. No proprietary format, no vendor lock-in.
- **No subscription.** One-time build, sync (when it lands) uses your own free Google Drive quota
  instead of a paid backend.
- **Offline-first.** Writing, dictation, and history all work with no internet connection.

## Platforms

v1 targets **Windows desktop and Android**. macOS, iOS, and Linux are architected for (the stack
is portable) but not built or shipped yet — see the Cross-Platform Roadmap in `PLAN.md` for the
full breakdown and what changes per platform when that day comes.

## Features

### Project & library management
- Local, file-based project library (`Documents/Narraity/`) — create, open, browse projects
- Dark / light / system theme
- Settings screen with a side-nav structure ready to grow (Appearance, Editor, Dictation now;
  Spell Check, Google Drive Sync, Export slotted in as later phases land)

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
- Multiple parallel **tracks** ("Main", "Backstory", a POV character's arc, ...), each toggleable so
  you can overlay or isolate whichever ones matter right now
- Events carry a freeform "when" (a real date, "Day 3", "Spring, Year 1" — whatever fits the story's
  own sense of time) plus notes, and can link to scenes, characters, and world entries
- A linked scene shows as a chip on the event card — tap it to jump straight to that scene in the
  manuscript editor

### Family Tree / Relationship Diagram
- Pan/zoomable canvas of your characters (pulled live from Character Profiles) with draggable
  positions that persist between sessions
- Relationships (family, romantic, friend, rival, ally, mentor, other, plus a custom label) drawn as
  labelled lines between characters
- **Drag one character's node onto another** to open the relationship dialog pre-filled with the
  dragged character and the one it landed on — editing the existing relationship between them if
  there already is one. The dragged node snaps back to its own position afterward; this gesture
  links, it doesn't move
- Add relationships via the "+" picker instead (pick both characters, a type, an optional label) when
  drag-and-drop isn't convenient; manage existing ones from a side list

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

## Tech stack

- **Flutter** + **Riverpod** for state
- **Local file storage** — JSON + Markdown, no embedded database
- **`diff_match_patch`** for Version History's diff/patch storage
- **`crypto`** + **`cryptography`** (HMAC-SHA256, Argon2id, AES-256-GCM) for history tamper-evidence
  and the password-protected Vault — no native platform dependency, works identically on every OS
- **`record`** (cross-platform mic capture) + a hand-written FFI binding for Windows dictation
- **`speech_to_text`** for Android dictation
- **`file_picker`** for choosing character/worldbuilding images
- No servers, no accounts, no telemetry — everything above runs entirely on-device

## Why not a Vosk Flutter plugin?

The only published `vosk_flutter_service` release has a build-breaking bug on Windows (its own
install script extracts the native DLL one folder deeper than its build script expects, and its
`CMakeLists.txt` also runs a stale command left over from a package rename). Rather than depend on
an unmaintained single-contributor package with that baked in, the real `libvosk.dll` — Apache
2.0, from the same upstream release — is vendored directly at `windows/vosk/`, with a ~150-line
hand-written FFI binding (`lib/services/vosk_ffi.dart`) covering the handful of functions actually
needed. Full writeup in that file's doc comment.

## Getting started (development)

```bash
flutter pub get
flutter run -d windows      # or -d <android-device-id>
```

Windows builds need the vendored DLLs in `windows/vosk/` (already checked in) — no extra install
step required, unlike the plugin this replaces.

Run the test suite:

```bash
flutter test
```

See `BUILD_LOG.md` for a phase-by-phase record of what's been built, and
`../../projects/Narraity/PLAN.md` for the full project plan (all phases, including ones not built
yet).
