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

## Manuscript structure generalization (post-1.7)

Replaced the fixed Act → Chapter → Scene model with a generic arbitrary-depth tree
(`ManuscriptNode`), chosen from a starter seed at project creation (5 presets + blank/custom) but
fully editable afterward. Every node can hold its own prose *and* have children at the same time —
the original container-vs-leaf split meant a node with prose couldn't gain subsections, which was a
real UX gap found after rebuilding and using the app live, not caught by tests. Fixed by dropping
`isContainer` entirely and renaming `leafIds` → `contentIds` (self + descendants, self first).
Forced simplifying Goal scoping too: `GoalScope.act`/`.scene` dropped (no consistent concept of
"act" once structure is freeform) — goals are now `project` or `global` only, with old act/scene
goals falling back to `project` scope on load rather than failing.

Verified live in the running Windows app: created a project with the "Chapters only" seed, added a
subsection under a chapter, and confirmed the chapter's own prose editor stayed reachable while
also showing the child — the exact case the redesign was for.

## Data protection — tamper-evidence, corruption resilience, password-protected vault

Started from the user asking how Version History's on-disk JSON format works, then walking through
a malware-tampering scenario and a corruption-recovery scenario. Design went through several real
pivots worth keeping for context:

1. **First attempt: per-device HMAC signing via `flutter_secure_storage`** (Windows DPAPI / Android
   Keystore). Caught during design review, not after building: a device-local key means a snapshot
   signed on Windows can never verify on Android once Drive sync brings the file across — false
   "tampered" flags on genuinely good history.
2. **Corruption resilience, separately from tamper-evidence:** content-hash verification on read,
   periodic full-text keyframes to bound replay depth, and a `.history_backup/` mirror folder for
   auto-repair when the primary copy fails verification.
3. **"Nearly guarantee integrity":** discussed content-addressed storage, redundancy across
   independent failure domains, active scrubbing, majority reconciliation — concluded nothing
   survives the whole machine being destroyed without a copy that leaves it.
4. **The actual answer, proposed by the user:** a password-protected Vault file as a second,
   independent backup artifact. This solves the cross-device problem too — a human password
   derives the same key on every device, unlike OS-specific secure storage.

**What got built:**
- `SceneHistoryService`: every snapshot HMAC-signed, chained to the previous snapshot's signature.
  On read, a signature/chain mismatch is treated as tampered (quarantined — renamed `.tampered`,
  never deleted) *unless* the `.history_backup/` mirror copy verifies clean, in which case the
  primary is auto-repaired from it. `SnapshotVerification` has three states: `valid`,
  `legacyUnsigned` (predates signing, or written with no password set — trusted, not flagged), and
  `locked` (has a real signature but no password unlocked this session to check it against — a real
  bug caught in review: without this third state, opening the app without the password would
  falsely flag genuinely signed history as tampered). `pruneAutoSnapshots` refuses to run if it
  would need to re-sign entries without having the key available, rather than silently downgrading
  them to unsigned.
- `HistorySigningKeyManager`: derives the signing key from the vault password via Argon2id — no
  OS secure storage at all. Deliberately not `flutter_secure_storage`: its Windows backend needs
  Visual Studio's ATL component (not installed here, and upgrading the package's major version
  didn't drop the requirement), and a device-local key can't verify snapshots synced from another
  device regardless.
- `VaultService`: password-protected AES-256-GCM archive of the whole project directory
  (Argon2id-derived key; GCM's auth tag is the tamper/corruption check, no separate signing scheme
  needed). Generational rotation (`refreshVault`, default 10 kept, configurable) so a single bad
  auto-refresh can't overwrite the last known-good backup.

**Verified:** 92/92 tests passing (added `vault_service_test.dart`, rewrote
`scene_history_service_test.dart` for the new signing API), `flutter analyze` clean, **both**
`flutter build windows` and `flutter build apk --debug` succeed — confirmed by actually running
each build, not just assumed from removing the offending dependency.

**Not built yet:** settings UI (enable vault, enter/change password, adjust retention count),
auto-refresh scheduling (the service call exists, nothing calls it on a timer or app-close yet),
restore-flow UI (decrypt + pick a generation + write back — the service methods exist, no screen
uses them), and per-project vault passwords (explicitly deferred — current design is one password
per library).

---

## Current status

Phases 0 through 1.7, the manuscript structure generalization, and the data protection work above
are all built, verified, and committed. 92 automated tests passing, `flutter analyze` clean, both
`flutter build windows` and `flutter build apk --debug` succeed. Commits: `3097c4b` (Phases
0/0.5/1), `bd27566` (dictation, goals, version history, manuscript generalization), `8416beb`
(data protection).

Next candidates per `PLAN.md`: Phase 2 (Character profiles, Worldbuilding, Story Notes) or Phase
2.5 (Reference Panel) — or the data-protection UI wiring listed above.
