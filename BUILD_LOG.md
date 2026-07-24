# Build Log

Chronological record of what's been implemented, phase by phase. See `PLAN.md`
(`projects/Narraity/PLAN.md`) for the full plan including phases not started yet, and `README.md`
for the current feature list.

All work below was built and verified (tests + a real run on Windows desktop) on **2026-07-24**.

---

## Phase 0 — Project scaffold

- Flutter project scaffolded (org `uk.aity`, Windows + Android v1 targets)
- File-based data model: `project.json` + the full folder skeleton (`manuscript/`, `characters/`,
  `worldbuilding/`, `plot-grid/`, `goals/`, `notes/`, `timelines/`, `relationships/`, `assets/`,
  `todos/`, `.sync/`) so later phases needed no migrations
- Library screen: create/open project, grid view
- Dark / light / system theme with persistence
- App shell (library <-> project navigation)

**Environment note:** the installed Visual Studio (2026, v18) postdates Flutter 3.35.5's known
CMake generator list. Patched one line in the local Flutter SDK copy
(`packages/flutter_tools/lib/src/windows/visual_studio.dart`) to map it to `Visual Studio 18 2026`
— `flutter upgrade` will need this reapplied.

## Phase 0.5 — Global Ideas

- Quick-capture dialog, reachable from the library and from inside a project
- `_GlobalIdeas/idea-<id>.json` storage at the library root
- Search + tag-filter list view
- Promote-to-new-project and attach-to-existing-project actions — the idea is marked "used," never
  deleted, seeding a story note in the target project

## Phase 1 — Manuscript editor

- Act/Chapter/Scene tree with drag-reorder (scenes), add/delete at every level
- Prologue/Epilogue/Dedication/Author's Note front/back matter
- Scene editor: debounced autosave to Markdown+front-matter files, formatting toolbar
  (bold/italic/strike/scene break/quote/heading), undo/redo, Find & Replace, live word count
- Focus Mode (Esc to exit)
- Editing-view font/size/line-spacing settings (persisted)
- Per-project to-do list

**Also added (not originally scoped):** a global error logger (`lib/services/app_logger.dart`)
catching Flutter framework errors, async errors, and uncaught exceptions to
`Documents/Narraity/.logs/app.log`, for easier debugging.

**Fixed during build:** a `ReorderableListView` nested inside an `ExpansionTile` collided on
`PageStorage` (its scroll-offset slot clashed with the tile's own expanded-state slot, throwing
`type 'bool' is not a subtype of type 'double?'`) — fixed with an explicit `PageStorageKey` per
chapter's scene list.

*(Git: `3097c4b` — "Initial commit: Phases 0, 0.5, and 1 complete")*

## Phase 1.3 — Voice-to-text dictation

Scoping decisions made before writing code (see chat history / PLAN.md's Phase 1.3 section):
- **Engine split:** Windows uses a hand-written Dart FFI binding directly to Vosk; Android uses
  native `SpeechRecognizer` via `speech_to_text`. Originally considered "one engine everywhere" via
  the `vosk_flutter_service` plugin, but that package's only release has a build-breaking bug on
  Windows (DLL extracted one folder deeper than its own build script expects, plus a stale
  auto-install command from a package rename) — see `lib/services/vosk_ffi.dart`'s doc comment for
  the full story. The real `libvosk.dll` (Apache 2.0, verified working) is vendored at
  `windows/vosk/` instead.
- **Model catalog:** resolved live against `alphacephei.com/vosk/models/model-list.json` rather
  than a hardcoded name/version — model names get superseded over time. A pinned last-known-good
  fallback covers the catalog being unreachable.
- **Model size choice:** Small (~40MB) or Large per language, added after the user asked for the
  choice explicitly. en-GB's "large" is its only non-small model (~281MB); en-US's true "big"
  model is ~1.8GB, so "large" there resolves to the ~124MB "lgraph" variant instead — the picker
  always resolves to "the smallest non-small active model," not a hardcoded name.
- **Model management moved into Settings** (see Phase: Settings restructure below) so users can
  switch language/accuracy or delete a downloaded model without re-triggering the first-use flow.

Built: `DictationEngine` interface, `VoskWindowsDictationEngine` (real mic capture via `record` +
FFI), `AndroidDictationEngine` (auto-restart across Android's silence timeout),
`VoiceCommandProcessor` (spoken punctuation → symbols), `DictationModelService` (download/list/
delete models), mic toggle + "review dictated text" indicator in the scene editor.

## Settings restructure

Added a proper Settings screen with a side-nav (`Appearance`, `Editor`, `Dictation` live now;
`Spell Check & Language`, `Google Drive Sync`, `Export` as "coming soon" placeholders matching
Phases 4.5/5/6) instead of one-off dialogs, per user request mid-session — anticipating settings
will keep growing as later phases land. Theme control moved here from the library app bar.

## Phase 1.5 — Adaptive Goal Engine

- `GoalCalculator`: pure, fully unit-tested daily-target math. Redistribution ("miss a day, target
  rises"; "get ahead, target eases off") isn't separate bookkeeping — it falls straight out of
  recalculating `remaining words ÷ remaining working days` fresh from the actual current word
  count every time.
- Goals scoped to project / act / scene, with a working calendar (recurring days off)
- Setup wizard: scope → target type → word count/deadline → working days → live preview
- Progress UI: today/overall rings, 30-day activity heatmap, delete
- **App-wide goals** (added after the user asked for it): a second scope, `GoalScope.global`,
  tracking word count across every project or a user-picked subset, via a separate
  `GlobalGoalsService` (`_GlobalGoals/goals.json` at the library root) and its own setup wizard
  with a project multi-select. `GoalProgressCard` was refactored to take callbacks instead of a
  `Project` + provider lookup so the same widget serves both per-project and app-wide goals.

**Fixed during build:** `Map.values.last` isn't reliable for "most recent daily-log entry" — Dart
maps preserve insertion order, not date order, and updating an existing key's value doesn't move
it to the end. Fixed with an explicit max-by-date scan (same fix applied in three places:
`GoalCalculator`, `GoalProgressCard`, and the heatmap cell).

## Phase 1.7 — Version History

- `SceneHistoryService`: auto snapshots (~30s idle or ~300 words changed, whichever first) and
  named checkpoints, stored as `diff_match_patch` patches against the previous *kept* snapshot —
  not full copies. Reconstructing any point replays the patch chain from the start; a `_latest.txt`
  cache avoids replaying the whole chain on every autosave check.
- `SnapshotPruner`: pure, unit-tested bucketing (last 48h kept whole; 48h–7d thins to one/hour;
  7d–30d to one/day; 30d+ to one/week). Checkpoints are never pruned.
- Pruning recompacts rather than deletes blindly: a pruned snapshot's diff is folded into its
  neighbor by recomputing the next surviving snapshot's patch directly against its new previous
  point, so the chain still reconstructs correctly with the pruned entries gone.
- Restore creates a *new* snapshot capturing the transition rather than overwriting — the restore
  itself shows up in the timeline and is itself undoable.
- History screen: timeline (newest first, auto vs. checkpoint distinguished), word-count
  sparkline, tap-to-diff (one snapshot vs. its predecessor, or two selected snapshots against each
  other) with insert/delete highlighting, one-click restore, "Save Checkpoint."

**Fixed during build (two real bugs, not test bugs):**
1. A test asserting pruning reduced snapshot count initially exposed a genuine correctness bug:
   naive tiered thinning could prune away the single most recent snapshot if it happened to land
   in an old bucket (e.g. a scene untouched for 60 days, all its snapshots in one weekly bucket) —
   silently reverting `reconstructContent`'s result to a stale point despite nothing being
   "deleted" on purpose. Fixed by making `SnapshotPruner.selectToKeep` always retain the single
   most recent timestamp regardless of its age/bucket.
2. Two of the test's own backdating helpers rewrote a snapshot's `timestamp` field without
   renaming the file to match (the id — and filename — is derived from the timestamp), leaving
   orphaned stale files and inflating snapshot counts. Test bug, not a service bug; fixed in the
   test.

---

## Current status

Phases 0 through 1.7 built and verified. 83 automated tests passing, `flutter analyze` clean. Only
Phases 0/0.5/1 are committed to git (`3097c4b`) — dictation, goals, and version history are on disk
but not yet committed, pending user confirmation.

Next candidates per `PLAN.md`: Phase 2 (Character profiles, Worldbuilding, Story Notes) or Phase
2.5 (Reference Panel).
