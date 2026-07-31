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

## Data-protection UI wiring

The service layer from the previous section was complete and tested but entirely unreachable from
the app: nothing set a password, `sceneHistoryServiceProvider` never passed the key manager (so no
snapshot was ever actually signed in the running app), nothing called `refreshVault`, and restore had
no screen. This session wired all of it in.

**Design decisions made during the build:**
- **Vaults live in `Documents/Narraity/_Vault/`, outside every project folder.** `buildVault` zips a
  whole project directory, so vaults stored inside one would seal every earlier generation into each
  new one. `LibraryService.listProjects` already skips `_`-prefixed folders, so it never appears as a
  project.
- **A verifier file was needed, and its absence was a real bug.** `unlock` previously returned void
  and accepted *any* password — the derived key was simply wrong, so the app would then sign new
  snapshots with a key that couldn't verify existing ones, surfacing later as tampering. Fixed by
  storing an HMAC of a fixed string under the correct key (`_Vault/verifier`); `unlock` now returns
  false on a mismatch and leaves any already-unlocked key alone.
- **The session has to hold the password, not just the derived signing key.** `VaultService`
  generates a fresh salt per vault file and derives its own key from the password, so unattended
  auto-refresh can't work from the signing key. Both now live in memory for the session, cleared on
  lock, never written to disk.
- **Restore writes to a new sibling folder, never in place** (user's call). A restore happens when
  something already looks wrong, which is exactly when destroying current state would be worst.
- **Password change re-signs before it rekeys.** Every snapshot's signature depends on the password,
  so changing it means re-signing the whole library. `SceneHistoryService.resignAll` verifies an
  entire project under the old key *before* writing anything, and the orchestration verifies *every*
  project before rewriting any — the stored verifier flips only after all of them succeed, since
  flipping it early would leave a library claiming a password that can't verify its own history. A
  mid-run write failure rolls already-migrated projects back to the old key. `resignAll` also refuses
  to re-sign an entry that doesn't verify: doing so would launder tampered content into apparently
  valid history, destroying the only evidence anything was wrong.
- **Skipping the unlock prompt is fully supported.** Locking someone out of their own manuscript
  because they can't recall a *backup* password would be far worse than an unsigned session, so
  declining leaves writing working normally (new entries unsigned, no auto-backup) and the prompt
  doesn't nag again that session.
- `Ref` and `WidgetRef` share no supertype in Riverpod 2, so the multi-provider operations live on a
  `VaultActions` class behind a provider rather than as free functions — otherwise the same helper
  couldn't be called from both a widget and the project shell's timer.

**Verified:** `flutter analyze` clean, **113 tests passing** (was 92), and *both* `flutter build
windows` and `flutter build apk --debug` succeed. New coverage:
`test/history_signing_key_manager_test.dart` (wrong password rejected, failed unlock doesn't clobber
the key, rekey swaps which password works, salt stays stable), `resignAll` cases in
`scene_history_service_test.dart` (re-signed history verifies under the new key, `_latest.sig` stays
consistent so later snapshots still chain, all scenes migrate, legacy-unsigned entries get upgraded,
a tampered entry aborts the run leaving every file byte-identical), and
`test/vault_flow_test.dart` — an end-to-end walk of the flows as the UI drives them: setup → signed
history → backup lands under `_Vault/` → simulated restart shows `locked` (not tampered) → wrong
password rejected, right one unlocks → history verifies → restore into a sibling folder → change
password → restart → only the new password works and nothing is falsely flagged.

**Caveat on verification:** the desktop app was built and launched, but the computer-use tooling on
this machine couldn't resolve the window, so the GUI was **not** clicked through by hand this time.
The flow test above covers the same provider calls the screens make, and a widget test confirms the
Backup & Vault section renders its first-time setup card — but the pixel-level walkthrough
(dialog layout, slider feel, snackbars) is still unconfirmed by eye.

**Not built yet:** per-project vault passwords (still one password per library, deliberately
deferred), and no "export vault to another drive" action — `buildVault` takes an arbitrary path, so
that's a UI-only gap.

---

## Phase 2 — Characters, Worldbuilding, Story Notes

The reference material the app was still missing, and the prerequisite for Phase 2.5's Reference
Panel (which has nothing to show without it). The Phase 0 project skeleton already created
`characters/`, `worldbuilding/`, and `notes/`, so nothing needed migrating.

**User decisions:** images included this phase; world entries grouped by category; notes get folders
*and* tags *and* search.

**Design decisions worth keeping:**
- **One `ProfileService` for both characters and world entries, not two.** They differ only in the
  folder, the id prefix, and which starter fields a new entry gets — every other behaviour (CRUD,
  images, categories) is identical, so two classes would have meant two of everything downstream and
  two places to fix each bug. Same reasoning for one `ProfilePanel` and one `ProfileEditor`. (The plan
  named separate `character_service.dart`/`world_service.dart`; collapsing them was a deliberate
  change once the duplication became obvious.)
- **Fields are an author-defined ordered map, not fixed properties.** Every writer wants a different
  character sheet, so a fixed schema would be wrong for most of them. `jsonDecode` preserves key
  order and every save rewrites the whole object, so the author's field order survives round-trips —
  and renaming a field rebuilds the map in place rather than moving that field to the end.
- **Note folders are real subdirectories, not a JSON field.** The structure stays visible and
  rearrangeable outside the app, which is the point of human-readable local-first storage. One level
  only: deeper nesting is a filing system, and search is the real answer to "where did I put that."
  A note's folder is derived from where its file actually sits.
- **Deleting a folder moves its notes to the root.** Removing a container must never destroy writing
  filed inside it.
- **Search uses a lazily built in-memory index, dropped on every write.** Notes have to be read to be
  listed anyway, so an on-disk index would buy no measurable speed at realistic sizes while adding a
  way for results to go stale — and "the note you know you wrote can't be found" is a much worse
  failure than a few milliseconds. Terms are ANDed (adding a word should narrow), and title hits
  outrank tag hits, which outrank body hits.
- **Images are copied into `assets/images/`, never referenced in place.** The original could be
  anywhere; a project has to stay self-contained to be portable and backup-able. Replacing an image
  deletes the old file first, since the new one may have a different extension and wouldn't overwrite
  it — and deleting an entry deletes its image, or it would be carried into every vault backup forever.
- **Folder names are sanitised against path separators**, or a name like `../escape` would write
  outside the notes folder entirely.
- **Scene selection and reference selection are separate providers.** Opening a character and closing
  it again returns you to the scene you were writing. Tapping a scene clears the reference selection
  (via a shared `openScene` helper) — without that, tapping a scene while a profile was open would
  look like it did nothing.
- Sidebar tabs went from 2 text labels to **5 icons**: five text tabs don't fit in 280px.

**Verified:** `flutter analyze` clean, **148 tests passing** (was 113), both `flutter build windows`
and `flutter build apk --debug` succeed. New coverage: `profile_service_test.dart` (starter templates,
field order round-trip, alphabetical listing, corrupt/hand-written files, categories, and the four
image behaviours above), `story_notes_service_test.dart` (CRUD, promoted-Global-Idea file shape,
folder create/move/rename/delete-moves-to-root, path-escape sanitising, and search: ranking,
narrowing, case-insensitivity, and index invalidation after edit/delete/move), a shell widget test
(five tabs; selecting a character routes the main pane to `ProfileEditor`), and an addition to
`vault_flow_test.dart` proving a backup carries characters, world entries, and foldered notes.

**Caveat on verification:** as last session, computer-use can't resolve the Narraity window on this
machine, so the GUI was not clicked through — the file-picker dialog, profile layout, and sidebar feel
are unconfirmed by eye. Everything reachable from the service and provider layers is covered by tests.

**Environment note:** `flutter clean` did *not* remove `build/` on this machine, and a stale
`build/app/intermediates/assets/debug/mergeDebugAssets` made `flutter build apk --debug` fail
repeatedly with a Gradle "unable to delete directory" error. Deleting `build/` outright fixed it.
Worth reaching for first next time rather than re-running clean.

---

## Phase 2.5 — Reference Panel

The differentiator Phase 2 was the prerequisite for: contextual character/world info docked beside
the editor, driven by `@` mentions and pins, showing only the fields starred as `quickRef`.

**The one decision that needed the user: what `@mention` inserts.** PLAN.md specified an id-based tag
(`[[char:elena-vance]]`), but real ids are uuids, and in a plain-text editor that tag sits visibly in
the middle of the sentence being written. Chose **name-based `[[Elena Vance]]`** (user's call): readable
in prose, wiki-style. The trade-off is explicit — renaming a character orphans existing mentions until
Find & Replace fixes them — and it's handled gracefully rather than silently: an unmatched mention
becomes an "unresolved" card offering to create that profile, which doubles as the natural path for a
character who shows up in the prose before they have a profile.

**Other design decisions:**
- **Mention parsing and `@`-query detection are a pure library** (`mention_scanner.dart`), no Flutter
  imports, so the fiddly parts are unit-tested rather than only reachable through a running editor.
  The `@` must follow whitespace or opening punctuation, so `elena@example.com` never triggers
  autocomplete, and a query stops matching once it spans a newline, a bracket, or 40 characters.
- **Keys are intercepted on the text field's own `FocusNode`, not an ancestor `Focus`.** An ancestor
  never sees Enter or the arrow keys in a multiline field — the field consumes them first — so the
  popup's keyboard navigation would silently not work.
- **Mentions publish on the save debounce, not per keystroke**, so the panel settles when you pause
  instead of flickering through partial names as you type. The publish is also diffed against current
  state to avoid pointless panel rebuilds.
- **Pins live in app preferences, keyed by project id, not in the project folder.** Pins are this
  machine's workspace state, not part of the manuscript — putting them in the project would ride them
  along into vault backups and (later) Drive sync. Keyed by id rather than folder name because a
  rename changes the folder.
- **Inline quick-edit resolves its service when editing starts**, so the debounced save can run from
  `dispose()` — where reading providers isn't safe — and captures the controller text before awaiting,
  since the controller may be disposed by the time the write lands.
- **Panel content is one derived provider** combining pins, mentions, and both entry lists, with
  `resolveMentions` extracted as a pure function (characters win a name collision with world entries;
  order follows mention order). Deleted entries silently drop out of the pin list rather than erroring.
- **Focus Mode hides the panel**, since the entire point of Focus Mode is nothing but prose on screen.
- The resize handle's visible divider is 1px but its grab area is 8px — a 1px drag target is painful.

**Deliberately deferred:** the autocomplete popup is anchored to the top of the editor area rather
than to the caret. Caret anchoring needs `TextPainter` geometry that has to be tuned by eye against a
running window, which this session couldn't do (see caveat) — a popup in a predictable place beats one
that lands slightly wrong. Worth revisiting alongside the rich-text editor, which will also be the
point at which `[[…]]` tags can be rendered as chips instead of raw brackets.

**Verified:** `flutter analyze` clean, **169 tests passing** (was 148), both `flutter build windows`
and `flutter build apk --debug` succeed. New coverage: `mention_scanner_test.dart` (14 cases:
extraction, de-duplication, nested/empty brackets, email non-trigger, newline/length limits, caret
mid-text), `reference_panel_provider_test.dart` (`resolveMentions` — case-insensitive matching, world
entries, character-wins collision, unresolved ordering), and a widget test proving a mentioned
character's starred field renders on a card with its value while unstarred fields stay hidden, and
that an unmatched mention offers "Create".

**Caveat, unchanged from the last two sessions:** computer-use can't resolve the Narraity window on
this machine, so the GUI was not clicked through. The panel's live feel — popup placement, drag-resize,
inline-edit focus behaviour — is unconfirmed by eye.

---

## Reference card id-guessing bug fix

Found by inspecting the user's own test data (no GUI needed): a hand-created worldbuilding entry
round-tripped correctly, but `ReferenceCard`/autocomplete were inferring character-vs-world by
checking `entry.id.startsWith('char-')` — a guess that breaks for any hand-edited or imported entry
with a different id (the project deliberately allows hand-editing files). Fixed by threading a
`ReferenceCardItem` (entry + `ProfileKind`) through `resolveMentions` and the panel/autocomplete pin
lookups instead of inferring downstream. 171 tests (was 169). Commit `3f1e79b`.

---

## Phase 3 — Plot Grid

Plot lines (colour-coded threads — main plot, subplots, POV arcs) crossed with manuscript scenes in
document order; each intersection can hold a plot point. Matches the `plot-grid/plotlines.json` +
`plot-grid/plotpoints.json` layout from PLAN.md's data model.

**What's built:**
- `lib/models/plot_grid.dart` — `PlotLine` (id, name, ARGB `color` int) and `PlotPoint` (id,
  plotlineId, sceneId, title, notes). No Flutter dependency, so the models are unit-testable without
  a widget test — same pattern as the rest of the data layer.
- `lib/services/plot_grid_service.dart` — CRUD for both files, same shape as `TodoService`.
  `setPlotPoint` is upsert-by-cell (one point per plotline/scene pair; writing to an already-filled
  cell overwrites rather than stacking a second card nobody could see). `deletePlotline` cascades to
  drop every point on it, so a deleted row never leaves orphaned cells behind.
- `lib/state/plot_grid_provider.dart` — service/list providers, plus `sceneColumnsProvider`, which
  walks the manuscript structure once to produce `(id, title)` pairs in document order. This is the
  grid's column source; the same id→title walk already existed twice (`project_shell_screen`'s
  `_titleFor` and `ManuscriptService._findTitle`) so this is a third copy rather than a shared helper
  — small enough not to worth a refactor across three files for it.
- `lib/screens/plot_grid_screen.dart` — a `Table` (rows = plotlines, columns = scenes) wrapped in
  nested horizontal/vertical `SingleChildScrollView`s, opened full-screen from a new AppBar icon next
  to Goals (Plot Grid needs real width, the same reason Goals isn't a sidebar tab). Empty cells show
  a faint "+"; filled cells show a colour-tinted card with the plotline's colour, tap to edit/delete.
  Add/edit plotline dialog offers an 8-swatch preset palette rather than a full colour picker — for
  "pick one of roughly this many visually distinct threads" a picker is overkill.

**Deliberately deferred:** a plot point whose scene gets deleted from the manuscript becomes
invisible (its column disappears) but isn't cleaned out of `plotpoints.json` — no cascade wired from
`ManuscriptService.deleteNode`/`deleteSpecialSection` back into the plot grid yet. Dead data, not
data loss; worth a cleanup pass if it turns out to matter in practice.

**Verified:** `flutter analyze` clean, **179 tests passing** (was 171) — new
`plot_grid_service_test.dart` covers plotline/point CRUD, cell-overwrite-not-duplicate, cascade
delete, and reorder. Both `flutter analyze` and `flutter build windows` succeed; `flutter build apk
--debug` not re-run this session (no Android-specific code touched).

**Not clicked through by GUI** — same standing caveat as Phases 2 and 2.5. Table layout, scroll-sync
between the two nested scroll views, and dialog feel are unconfirmed by eye.

---

## Phase 3.5 — Timeline & Relationship Diagram

Two features from PLAN.md's `3.5` row, built together since both are "a canvas of things pulled from
other data plus a lightweight own file format": in-story chronology, and character relationship
mapping.

**Timeline** (`lib/models/timeline.dart`, `lib/services/timeline_service.dart`,
`lib/state/timeline_provider.dart`, `lib/screens/timeline_screen.dart`):
- `TimelineTrack` (a parallel strand — "Main", "Backstory", a POV arc) and `TimelineEvent`
  (trackId, label, freeform `timeLabel`, `order`, notes, linked scene/character/world id lists),
  stored as individual `timelines/timeline-<id>.json` / `timelines/event-<id>.json` files
  (`TimelineService` distinguishes them by filename prefix when scanning the directory) — matches
  PLAN.md's data model.
- **`timeLabel` is freeform text, not a parsed `DateTime`.** In-story time often isn't a real
  calendar (flashbacks, secondary-world calendars, "three years before the war"), so PLAN.md's "date
  or relative-time marker" is treated as author-controlled text; `order` (an int, ascending per
  track) is what actually drives left-to-right position, moved with the same
  swap-with-neighbour contract as `PlotGridService.reorderPlotline` and `ManuscriptService`'s
  reordering.
- Screen: one horizontally-scrolling row per track, `FilterChip`s at the top toggle track visibility
  (the PLAN.md "toggleable and overlayable" requirement) — not persisted, since a hidden track
  silently missing on next open would be worse than always starting with everything visible.
- A linked scene renders as a chip on the event card; tapping it pops the Timeline screen and calls
  the existing `openScene()` helper from Phase 2.5's reference plumbing — "click → jump to scene"
  from PLAN.md, reusing rather than reinventing scene navigation.
- Event editor's scene/character/world pickers reuse `sceneColumnsProvider`, which existed in
  `plot_grid_provider.dart` for the Plot Grid — moved to `manuscript_provider.dart` (its natural
  home) now that a second feature needs it, rather than writing a fourth copy of the manuscript-walk
  logic that already existed three times (`project_shell_screen`, `ManuscriptService`, and the Plot
  Grid's prior copy).
- **Not done:** PLAN.md's "Feeds the Reference Panel — an event card can display like a
  character/world card" — the Reference Panel's `@mention` trigger is built around named profile
  entries (Phase 2.5), and events don't have that kind of identity in scene prose. Left for a later
  pass rather than forcing a fit.

**Relationship Diagram** (`lib/models/relationship.dart`, `lib/services/relationship_service.dart`,
`lib/state/relationship_provider.dart`, `lib/screens/relationship_screen.dart`):
- Nodes are pulled live from Character Profiles (Phase 2), not stored separately. Edges are
  `Relationship` (characterAId, characterBId, `RelationshipType` enum + optional freeform `label`),
  stored as `relationships/relationship-<id>.json`.
- **Deviates from PLAN.md's literal data model**, which puts a `position` field on the relationship
  record. Position is a property of a *node* (a character), not an *edge* — a character with two
  relationships (or none yet) can only have one canvas position — so it's stored separately in
  `relationships/layout.json` keyed by character id instead. Documented in the model file's doc
  comment; same kind of considered deviation as Phase 2.5's name-based mentions.
- Canvas: `InteractiveViewer` (pan/zoom) over a `Stack` of draggable character cards, positions
  falling back to a deterministic grid layout for any character not yet dragged (stable across
  rebuilds since it's index-based, not random) so nodes don't jump around before the first drag.
  Edges are drawn with a `CustomPainter` connecting node centers, labelled with the relationship type
  (+ custom label if set) at the midpoint.
- **Simplified from PLAN.md's "draw a connection" gesture**: rather than a freehand tap-node-A-then-
  node-B canvas gesture (fragile to get right without a GUI pass to tune it), new relationships come
  from a picker dialog (two character dropdowns + type + label), and existing ones are edited/deleted
  from a side list rather than by tapping the drawn line — line hit-testing would need the same
  eyes-on tuning the mention-popup anchoring needed in Phase 2.5, which isn't available this session.
- **Not done:** deleting a character doesn't cascade into `relationships/` — a deleted character's
  edges and layout entry become dead data (same category of gap as the Plot Grid's scene-delete
  cascade, and `RelationshipService.removeNodePosition` exists but nothing calls it yet). PLAN.md's
  "mini relationship view in the Reference Panel when viewing a character" also not wired —
  `RelationshipService.relationshipsFor(characterId)` exists and is tested, ready for a future
  `ProfileEditor` addition.

**Verified:** `flutter analyze` clean, **196 tests passing** (was 179) — new
`timeline_service_test.dart` (9 cases: track/event CRUD, per-track order independence, move/no-op at
boundary, cascade delete) and `relationship_service_test.dart` (8 cases: edge CRUD,
`relationshipsFor` both-sides matching, layout persistence/overwrite/removal). Both `flutter analyze`
and `flutter build windows` succeed; `flutter build apk --debug` not re-run this session (no
Android-specific code touched).

**Not clicked through by GUI** — same standing caveat as Phases 2, 2.5, and 3. The canvas drag feel,
edge-label legibility, and track-toggle layout are unconfirmed by eye; the "draw a connection" and
Reference Panel gaps above are exactly the kind of thing a GUI pass would likely reshape.

---

## Plot Grid: first real GUI bug, found by the user clicking through the built app

The user launched the built `narraity.exe` for the first time (across every phase — the standing
"not clicked through by GUI" caveat had been true since Phase 0) and reported the Plot Grid showing
nothing after adding two plotlines: no name text, no colour dot, rows collapsed to a sliver.

**Two real, independent bugs**, both in `lib/screens/plot_grid_screen.dart`'s `_Grid` widget:

1. **`Table(defaultVerticalAlignment: TableCellVerticalAlignment.fill)` with every cell set to
   fill.** "Fill" tells `Table` "don't ask me for a height, just stretch me to whatever the row ends
   up being" — during row-height computation `Table` only measures cells that *do* have a height
   opinion (top/middle/bottom), so with every cell set to fill, none of them ever assert a height,
   and the row-height pass has nothing to work from. Every row computed to **zero height**, then that
   zero got force-fed back down into every cell's constraints — overriding the `SizedBox(height:
   72)`/`SizedBox(height: 48)` each cell used to declare its own size (`RenderConstrainedBox`
   intersects its own wish with the incoming parent constraint, and the incoming constraint always
   wins). Confirmed via `RenderTable.toStringDeep()` inside a widget test: `"row offsets: 0.0, 0.0,
   0.0"`. Fix: dropped `defaultVerticalAlignment` entirely — the default (`top`) measures each cell's
   real intrinsic height instead of asking it to just fill an already-computed row height.
2. **Nested `SingleChildScrollView`s (vertical outer, horizontal inner) with no bounded size handed
   between them** — a separate, known Flutter footgun: the inner horizontal view needs a *bounded
   height* from its parent, but a bare vertical-then-horizontal nesting leaves that unbounded. Debug
   builds throw a large red assertion for this; `flutter build windows` compiles release, which
   strips the assertion, so it silently degenerated the layout instead of failing loudly — exactly
   the kind of bug that would never surface without an actual GUI pass. Fixed by swapping the nesting
   order (horizontal outer, vertical inner) and wrapping the inner view in a `SizedBox` with the
   table's known total width (`plotlineColumnWidth + columns.length * sceneColumnWidth`), which gives
   the inner view the bounded cross-axis constraint it needs.

**New regression coverage:** `test/plot_grid_screen_test.dart` pumps the real screen (not just the
service layer) with a temp project and asserts actual pixel size (`tester.getSize(...).height >
8`), not just tree presence — `find.text(...)` alone would have passed even on the fully collapsed
original layout, since the widget was still *present* in the tree, just laid out at zero size. This
is the general lesson from this bug: `flutter analyze` + `flutter test` + `flutter build windows`
succeeding, as reported for every phase from 0 through 3.5, verifies the code compiles and the
service/logic layer is correct — it does **not** verify a screen actually renders visible content.
Every "not clicked through by GUI" caveat in this log up to now should be read with that in mind.

**Verified:** `flutter analyze` clean, **197 tests passing** (was 196 — the one new widget test).
Rebuilt `flutter build windows`, confirmed the render tree shows non-zero row offsets.

---

## Relationship Diagram: drag-and-drop linking, and a second real GUI bug

User feedback after the Plot Grid fix: dragging one character node onto another should open the
relationship dialog with the dragged character as A and the one it landed on as B (editing the
existing relationship if one's already there), rather than only offering the "+" picker-dialog flow.
Kept the "+" icon as-is alongside it.

**While wiring this up, found that node dragging had never actually worked at all** — not new
today, a bug present since the original Phase 3.5 commit. Confirmed with a throwaway diagnostic
widget test: simulating a drag over a node produced no visible reaction whatsoever, not even
`setState` firing. Root cause: the node's `GestureDetector.onPanUpdate` creates a
`PanGestureRecognizer`, which competes in the same gesture arena as `InteractiveViewer`'s own
internal scale/pan recognizer for the same pointer — and `InteractiveViewer` was winning that race
every time, since both recognizers only accept once they see movement past a touch-slop threshold,
and `InteractiveViewer`'s apparently resolves first. Fixed with a custom
`_ImmediateDragRecognizer extends OneSequenceGestureRecognizer` that calls
`resolve(GestureDisposition.accepted)` synchronously inside `addPointer` — claiming the pointer the
instant it touches down, before `InteractiveViewer`'s movement-triggered recognizer gets a chance to
compete at all. Wired in via `RawGestureDetector` in place of the plain `GestureDetector`.

**What's built:**
- Dragging character A's node onto character B's opens the relationship dialog pre-filled A→B (or
  the existing relationship between them, edit mode, if one already exists) — checked via a rect
  containment test against the other nodes' *persisted* positions (not live drag positions of
  siblings, since only one node is ever being dragged at a time).
- The dragged node **snaps back to its saved position** rather than staying wherever it was dropped
  — this gesture's purpose is linking, not moving, so the position is reset in local state before the
  disk write that would otherwise never happen (dropping on a node never calls `setNodePosition`).
- A small "→ {target name}" label appears on the dragged card while hovering over a valid drop
  target, plus a highlighted border, so the gesture has feedback before release.
- `_showRelationshipDialog` gained optional `presetCharacterAId`/`presetCharacterBId` params (used
  only when not editing an existing relationship) so both the "+" picker flow and the new drag flow
  share one dialog implementation.

**New regression coverage:** `test/relationship_screen_test.dart` — drags one node onto another and
asserts (a) a hover indicator appears mid-drag (proving the gesture actually reaches the node, which
is exactly what silently failed before the fix), (b) the relationship dialog opens, and (c) the
dragged node's position afterward equals its position before the drag (the snap-back). Deliberately
does **not** tap Save through to a real write — same reasoning as `widget_test.dart`'s "New Project
dialog" test: real file I/O triggered from a simulated tap runs inside flutter_test's fake-async zone
and never resolves, so persistence is left to `relationship_service_test.dart`'s existing
`addRelationship`/`saveRelationship` coverage. Confirmed this the hard way — an earlier version of
this test that awaited a provider `.future` after tapping Save hung until the test-runner's own
timeout killed it.

**Verified:** `flutter analyze` clean, **198 tests passing** (was 197). Rebuilt `flutter build
windows`.

**Lesson reinforced:** this is the *second* real bug this session found only by an actual GUI/gesture
pass — neither the missing-height Table bug nor this gesture-arena conflict would ever show up in
`flutter analyze`, `flutter test`, or `flutter build`, all of which had been reporting clean/passing
for this exact code since it was first committed. Every phase's "not clicked through by GUI" caveat
in this log should be read as "the interactive behaviour is unverified," not just "the visuals are
unconfirmed."

---

## Relationship Diagram polish: colour-coded lines, badge labels, drag responsiveness

Follow-up feedback after the drag-and-drop session: colour-code the lines by relationship type,
render the label as a badge sitting on top of the line rather than raw text, and the drag felt
unresponsive.

**Colour coding:** `_relationshipTypeColors` maps each `RelationshipType` to a colour (reusing the
Plot Grid's palette hues for a consistent feel across the app), applied to the line itself, a small
dot on each side-list row, and a dot on each option in the dialog's Type dropdown — so the same
colour means the same thing everywhere in the screen, not just on the canvas.

**Badge label:** `_EdgePainter` now draws a filled, rounded-rect badge (theme surface colour, with a
1px border in the relationship's own colour) centred at the line's midpoint, drawn *after* the line
so it visibly sits on top, then the label text on top of that. Previously the label was raw text
painted directly over the line with no background, illegible wherever a line crossed under it.

**Drag responsiveness:** the gesture itself was already firing on every pointer move
(`_ImmediateDragRecognizer` from the prior fix), but the **edges never followed the dragged node
live** — `_EdgePainter` only read from the persisted/fallback `layout`, which doesn't change until
the drag ends and the provider re-fetches. So the card moved instantly but every line attached to it
stayed frozen at the old position until release, then jumped — which reads as sluggish even though
the underlying gesture recognition wasn't the actual bottleneck. Fixed by promoting drag state from
purely-local (`_DraggableNodeState._dragPosition`) up to `_Canvas` (now a `ConsumerStatefulWidget`
tracking `_draggingId`/`_draggingPosition`), fed by a new `onDragUpdate`/`onDragEnd` callback pair on
`_DraggableNode`. The dragged node keeps its own local state too (for its own snappy re-render
without waiting on the parent), so this is additive, not a behaviour change to the drag itself — the
node moves exactly as it did before, the edges just now move with it.

**Verified:** `flutter analyze` clean, all 198 tests still passing (behavioural change, not new
surface area — the existing `relationship_screen_test.dart` drag/dialog/snap-back test still covers
the gesture path). Rebuilt `flutter build windows`.

---

## Relationship Diagram: fix drag tracking, add New Character

Follow-up feedback: the drag still lagged behind the cursor, and creating a character belongs on this
screen too (mapping relationships is exactly when you notice someone's missing).

**Drag lag — real second bug, not the same one as before.** The prior fix made the *gesture* fire on
every pointer move; this one was about what the handler *did* with those events. It accumulated raw
screen-pixel deltas (`event.position - lastPosition`) and applied them directly as canvas-local
position deltas. That's only correct at the default unzoomed, unpanned view — `InteractiveViewer`
scales its child, so a delta measured in screen pixels doesn't equal the same delta in the canvas's
own coordinate space once the user has zoomed (a screen-pixel delta is worth *more* local-space
movement when zoomed out, *less* when zoomed in), producing exactly the lag/overshoot reported.

Fixed by switching from delta-accumulation to grab-offset anchoring: `_ImmediateDragRecognizer` now
reports raw absolute pointer positions (`onDown`/`onMove`) instead of deltas; `_DraggableNodeState`
converts each one to true canvas-local coordinates via `RenderBox.globalToLocal` (using a
`GlobalKey` on the canvas `Stack`, exposed as `_CanvasState._globalToLocal`), and captures a
`_grabOffset` — the local-space offset from the node's top-left to wherever the user actually
clicked — on pointer-down. Every subsequent frame sets the node's position to
`localPointerPosition - grabOffset`, so the exact pixel under the cursor never moves relative to the
cursor, regardless of pan/zoom level. This is a *correctness* fix (right coordinate space), not a
tuning one — there was no slop/threshold/sensitivity setting to turn up; the recognizer was already
maximally responsive (fires on every move, accepts immediately on touch-down), it was just computing
the wrong number.

**New Character button:** AppBar icon (`person_add_alt_1`) next to "New Relationship" opens a plain
name-prompt dialog and calls `ProfileService.create` — the same creation path the Characters tab
uses, just reachable from here too. New characters render at the deterministic grid fallback position
until dragged.

**Verified:** `flutter analyze` clean, **199 tests passing** (was 198 — one new widget test covering
the New Character dialog opening; per the established convention, the dialog is not driven through to
a real Save/write in a widget test, since that's real file I/O triggered from a simulated tap and
never resolves under flutter_test's fake-async zone). Rebuilt `flutter build windows`.

---

## Timeline: freeform canvas, track reordering, staggered events

User feedback after confirming the Timeline works: they want to reorder tracks themselves, and freely
move event cards within a track (not just nudge left/right) so a "staggered" layout is possible when
several events cluster close together in time — closer to a grid-type layout, but without actually
rendering a visible grid.

**Data model changed** (`lib/models/timeline.dart`): `TimelineTrack` gained `order` (int, row
position — reordered by swapping with a neighbour, same "nudge one step" contract as the rest of the
app's reordering, not a freeform index). `TimelineEvent` swapped its `order` (int, strict left-to-right
sequence) for `x` (double, free horizontal position — time reads left-to-right but nothing snaps to a
column) and `yOffset` (double, vertical offset from its *own track's* baseline row — this is what
enables staggering, since a card at `yOffset: -40` sits above the line, `+40` below it, without
leaving its track). `TimelineEvent.fromJson` reads a legacy `order` field as a one-time fallback
(`x = order * 180`) so events created before this change don't all pile up at `x=0` the first time
their project reopens; new writes only ever produce `x`/`yOffset`.

**Service** (`lib/services/timeline_service.dart`): `listTracks()` now sorts by `order` (id as
tiebreaker, for determinism when several legacy tracks share `order: 0`); `addTrack` appends at the
end; new `moveTrack(id, delta)` mirrors the existing swap-with-neighbour pattern. `addEvent` now
places new events to the right of whatever's already on their track (not at `order + 1`) and always at
`yOffset: 0` (on the baseline, until dragged). New `setEventPosition(event, x, yOffset)` persists a
drag in one write, replacing the old `moveEvent(id, delta)`.

**Screen rewrite** (`lib/screens/timeline_screen.dart`): moved from a `ListView` of tracks each with a
horizontally-scrolling row of cards, to a shared canvas — `InteractiveViewer` + `Stack`, tracks are
rows (each a thin baseline line, deliberately *not* a bordered grid — "the grid should not actually be
shown"), and event cards are `Positioned` and freely draggable in both axes with the exact same
grab-offset + `RenderBox.globalToLocal` technique the Relationship Diagram uses (see its two GUI-pass
bug fixes above) — dragging tracks the cursor precisely at any zoom level from the start, rather than
needing a second follow-up fix for lag. Track management (visibility toggle, up/down reorder, add
event, delete) moved into a right-hand sidebar, mirroring the Relationship Diagram's canvas+side-list
layout, since a "grid of rows" needs somewhere to manage the rows that isn't the canvas itself.

**Shared code:** extracted `ImmediateDragRecognizer` out of `relationship_screen.dart` into
`lib/widgets/immediate_drag_recognizer.dart` — a second screen needing the exact same
"claim-the-pointer-before-InteractiveViewer-does" gesture fix was the point at which duplicating it a
second time stopped being worth it (same threshold as `sceneColumnsProvider`'s move to
`manuscript_provider.dart` in Phase 3.5).

**Verified:** `flutter analyze` clean, **203 tests passing** (was 199) — `timeline_service_test.dart`
rewritten for the new model/API (freeform placement, `setEventPosition`, `moveTrack`/row-order
sorting); new `timeline_screen_test.dart` drags an event card diagonally and asserts it actually moved
in *both* axes (`dx` and `dy` independently, proving free 2D movement rather than a left/right nudge),
plus a sidebar test confirming the first track's "move up" and the last track's "move down" are
disabled. Rebuilt `flutter build windows`.

---

## Timeline follow-up: fix track reorder, connector lines, drag-to-swap-track

Three pieces of feedback right after the freeform rework: the sidebar's up/down track-reorder arrows
didn't do anything; events should show a line back to their track so a staggered card's home track is
still obvious; and dragging a card onto a different track's row should reassign it there.

**Track reorder arrows — real bug, not cosmetic.** `TimelineService.moveTrack` swapped the `order`
*values* between two tracks — correct in general, but every track that already existed before this
session's track-ordering feature defaults to `order: 0` (no field in its old JSON). Swapping `0` with
`0` is a no-op: the buttons visibly did nothing for the user's existing project, which is exactly what
was reported. Fixed by having `moveTrack` re-sequence *every* track to distinct values (`0..n-1`,
matching current display order) before performing the swap — self-healing, only needs to happen the
first time a project's tracks are reordered post-upgrade. New test creates two tracks with the same
`order: 0` (via `saveTrack` directly, bypassing `addTrack`'s auto-increment, to reproduce the
degenerate state) and confirms `moveTrack` still reorders them.

**Connector lines** (`_ConnectorPainter` in `timeline_screen.dart`): a line from each card to its own
track's baseline, anchored from whichever card edge (top or bottom) is nearer the line so it doesn't
cut through the card, plus a small dot marking where it meets the baseline. Drawn between the baseline
lines and the cards in the `Stack` so cards visually sit on top of their own connector.

**Drag-to-reassign:** dragging a card past the midpoint between two tracks' baselines now reassigns it
to the nearer one on release — `_nearestTrackId(y, baselineByTrackId)` picks the closest baseline,
used both to decide the actual reassignment and, live during the drag, to preview which track the
connector will snap to (the connector's target track — and therefore which baseline it's drawn to —
updates in real time as you drag, before you even release). Required promoting drag state from
purely-local to `_TimelineCanvas` (now tracking `_draggingEventId`/`_draggingTopLeft`, fed by
`onDragUpdate`/`onDragEnd` on `_EventCard`) — the same "lift state up so a painter can see it live"
pattern the Relationship Diagram's edges already use, and for the same reason (a connector that only
updates after the drag ends, not during, would read as sluggish the same way the Relationship
Diagram's edges did before that fix).

**Model/service:** `TimelineEvent.trackId` is no longer `final`; `copyWith` gained an optional
`trackId` param. `TimelineService.setEventPosition` gained an optional named `trackId` — when given,
reassigns in the same write as the position update; when omitted, the event stays on its own track
(existing callers unaffected).

**Verified:** `flutter analyze` clean, **207 tests passing** (was 203) — new service tests for the
degenerate-order reorder fix and for `setEventPosition`'s track-reassignment (both with and without a
`trackId`), new widget test dragging a card past a row's midpoint and confirming it lands near the
next track's baseline. Rebuilt `flutter build windows`.

---

## Phase 4 — Comments, highlights, sticky notes, footnotes; AI/external review round-trip

Built across three commits in one extended session: `8adcd8a` (shared anchor mechanism), `cdaab87`
(wiring it into the editor), `a9cc096` (the export/import round-trip plus a standalone reviewer
tool). 207 → 269 tests over the phase, `flutter analyze` clean throughout, `flutter build windows`
verified after each commit.

**✅ Foundation (`8adcd8a`).** `lib/models/annotation.dart` — one `Annotation` model (`AnnotationKind`
enum: comment/highlight/stickyNote/footnote) serving all four sub-features, same "one model, kind
enum" precedent as Phase 2's `ProfileEntry`/`ProfileKind`. `TextAnchor` is a `[start, end)` character
range plus a `quotedText` snapshot, with `resolveIn(content)` returning `exact` (offsets still
match), `moved` (text found verbatim at a different offset — content shifted around it), or
`orphaned` (text genuinely gone; clamped offsets are a display-only fallback, never persisted as if
real). Zero-length anchors are footnote point-markers. `AnnotationService` (`annotations/
annotations.json`, single array like `PlotGridService`) does CRUD plus `resolveForScene`, which
self-heals `moved` offsets by persisting the correction and leaves `orphaned` ones alone. Deliberate
deviation from PLAN.md: lives in a new `annotations/` folder, not the literal `notes/note-<id>.json`
the plan specifies — `notes/` is already Story Notes' (Phase 2) folder-and-tag system. Cascade delete
wired proactively into `ManuscriptService.deleteSceneFile` (unlike Plot Grid/Relationship Diagram,
where that gap was left for later).

**✅ Editor wiring (`cdaab87`).** `AnnotationHighlightController` (custom `TextEditingController`)
paints highlight/comment/sticky-note ranges as background tints directly in the plain-text editor —
no rich-text delta model needed. `AnnotationPanel` lists a scene's annotations with jump-to/delete/
resolve-toggle. Wired into `SceneEditor` with toolbar actions and `resolveForScene` called on scene
load. **Two real bugs found on first click-through, both fixed same session:**
1. Five separate toolbar icons overflowed the toolbar's plain (non-scrolling) `Row`. **Release builds
   silently swallow `RenderFlex` overflow** — the debug overflow-stripe painter is wrapped in an
   `assert`, stripped in Release — so the trailing icons (including the one that opened the
   annotations panel) just vanished with zero visual error. First fixed by collapsing five icons into
   one `PopupMenuButton`; when the user later asked for separate icons again (see below), the toolbar
   Row was wrapped in a horizontal `SingleChildScrollView` instead — the actual root-cause fix, so
   icon count can grow without this recurring.
2. Add Footnote silently no-op'd when the editor had never been focused (`TextSelection.invalid`),
   unlike the other three actions which already showed a "select some text first" snackbar.

**✅ AI/external review round-trip + reviewer tool (`a9cc096`).** `ReviewExportService` builds
Markdown with a `<!-- id: <sceneId>-p<NNN> -->` marker per paragraph (`paragraph_splitter.dart`, pure
blank-line splitter), merging each paragraph's `TextAnchor` into a persistent `review/anchors.json`
store (never sent to the reviewer — the export file only carries ids). `importComments` parses a
reviewer's `{"comments": [{"anchorId","text","category"?}]}` reply and creates ordinary
`AnnotationKind.comment` annotations, reusing the existing exact/moved/orphaned resolution instead of
building a separate "nearest paragraph" fallback — a deliberate deviation from PLAN.md's literal
wording, since whole-content substring search is a strictly finer-grained version of the same idea.

User feedback reshaped the UI twice during this build:
- First pass put single-scene Export/Import in the scene editor toolbar. User wanted multi-scene
  selection and a location outside the editor entirely — landed on `ReviewExportScreen` (checklist
  over `sceneColumnsProvider`, Select All/Clear), reached via a new icon in the project's top app bar;
  the per-scene toolbar icons were removed once this screen subsumed them.
- Second round: the user pointed out the real gap was the **reviewer's** side — a 3rd party with just
  the exported `.md` needs a tool that works with **no Narraity project or account at all**. Built
  `ReviewSessionsScreen`/`ReviewSessionDetailScreen`, reachable from the **Library screen** itself
  (top app level, before opening any project). Sessions persist to `_ReviewSessions/` at the library
  root — same "works without a project open" convention as Global Ideas' `_GlobalIdeas/` — so a
  review in progress survives closing the app, per explicit request ("keep it as a proper section").
  `review_markdown_parser.dart` parses the exported file back into paragraphs; comments collected
  per-paragraph via a dialog (text + optional category), autosaved on every edit; "Export Comments"
  writes the exact JSON `importComments` expects, plus a "Copy Path" snackbar action.
- Third addition: export now embeds project title/subtitle/author/export-timestamp — a
  human-readable header plus a hidden `<!-- narraity-review-export {...json...} -->` comment,
  invisible to `parseReviewMarkdown`'s paragraph collection. `ReviewSession.metadata` carries it
  through so the reviewer's session list and detail screen show whose work they're looking at, and
  `createFromMarkdown` prefers the embedded project title over the filename-derived fallback.

Email/sharing the exported file directly from the app was raised and deliberately deferred — logged
in `CONSIDERATIONS.md` — full SMTP/credential setup is a meaningfully bigger, separate feature; a
"Copy Path" snackbar action is the cheap version for now.

**269 tests** (was 207 at the start of the phase).

**✅ Read Aloud (text-to-speech) — `1e7abc7`.** Phase 4's last unbuilt sub-feature. Adds
`TtsService`, a thin wrapper around the `flutter_tts` package — the OS's built-in speech engine on
both v1 platforms (Windows WinRT voices, Android `TextToSpeech`), no model download needed unlike
dictation's Vosk models. Unlike the Vosk Flutter plugin this project replaced with a hand-written FFI
binding (see "Why not a Vosk plugin?" above), `flutter_tts` ships a real native Windows
implementation, so no such workaround was needed here.

Wired into the scene editor as its own toolbar icon next to dictation's mic (input vs. output —
same pairing logic as the rest of that toolbar section). Reads from the caret position (or the
start of the scene if none), and extends `AnnotationHighlightController` with a transient "speaking
range" — a plain `(start, end)` pair, not an `Annotation`, since it changes on every word boundary
and is never persisted. Implemented as a genuine overlay (splits and re-merges whichever annotation
spans it crosses) rather than a second competing "first wins" range, so a highlight or comment
underneath stays visible while its words are read. Auto-stops on a real edit (offsets after the edit
point go stale) or a scene switch. Settings → Read Aloud adds voice/speed/pitch controls, persisted
the same way as `EditorSettings`.

**A real bug found while fixing test fallout, worth remembering:** caching the `TtsService` eagerly
in `initState` (mirroring the `_vaultActions = ref.read(...)` pattern from the project shell) made
every `SceneEditor` mount create the platform plugin merely to populate the cache — and the
provider's disposal unconditionally called `stop()`, which threw `MissingPluginException` in the
test environment (no `flutter_tts` mock) for tests that never touched Read Aloud at all. Fixed by
creating the service lazily, only on first actual use — the eager-cache pattern is fine for
something like vault actions that's always needed, but wrong for a plugin only a fraction of
sessions will ever touch.

**One-time environment gap, fixed with the user's explicit OK:** `flutter_tts`'s Windows plugin needs
`nuget.exe` on PATH at *build* time (its CMake fetches `Microsoft.Windows.CppWinRT` via NuGet) — not
installed on this machine. Downloaded from the official NuGet distribution to
`Development/tools/nuget.exe` (not on PATH persistently — prefix `export PATH="…/tools:$PATH"` before
any future `flutter build windows` until that's fixed properly). Doesn't affect Android builds (a
wholly separate native implementation, ordinary Gradle) or end users on either platform — WinRT
speech synthesis ships with Windows itself, same as how Vosk models are the only "extra" thing users
ever download, and even that's unrelated.

**279 tests** (was 269) — pure-logic coverage for the raw-platform-response parser
(`parseTtsVoices`) and the highlight controller's new overlay behavior (paints with no annotations
present, overlays on top of an existing highlight rather than replacing it, clears cleanly). `flutter
analyze` clean, `flutter build windows` verified, and **the user confirmed it works live**: reading
from the caret, live word highlighting, voice/rate/pitch settings, clean stop on both manual stop and
typing.

---

## Phase 4.5 — Spell check (Hunspell, en-GB)

**✅ Built and committed 2026-07-25, commit `a43ee44`.** Scoped to spell check only this session
(thesaurus/dictionary via Open English WordNet deferred as its own follow-up, per user direction —
this phase has two large, mostly-independent pieces).

**No Dart/Flutter package wraps Hunspell at all** — checked pub.dev directly for a dozen likely
names (`hunspell`, `flutter_hunspell`, `hunspell_dart`, `nuspell`, ...), none exist. Same path as Vosk
dictation: a hand-written FFI binding to a native library. Unlike Vosk, there was no broken plugin to
route around — `libhunspell.dll` simply doesn't exist prebuilt anywhere trustworthy, so it's built
from source.

**Build recipe (Windows), reproducible from scratch:**
1. `git clone --depth 1 https://github.com/hunspell/hunspell.git` — ships its own MSVC solution
   (`msvc/Hunspell.sln`), no CMake/vcpkg needed.
2. This machine's Visual Studio ("18"/2026) doesn't match any of the solution's built-in
   `PlatformToolset` values (v140/v143) — its actual toolset name is `v145` (found via
   `MSBuild\Microsoft\VC\v180\Platforms\x64\PlatformToolsets\v145\Toolset.props`), and its Windows SDK
   is `10.0.26100.0`, not the project's default `8.1`. Retarget both:
   `sed -i 's/<WindowsTargetPlatformVersion>8.1</<WindowsTargetPlatformVersion>10.0</'
   msvc/libhunspell.vcxproj`, then build with `/p:PlatformToolset=v145` explicitly.
3. `MSBuild.exe msvc/libhunspell.vcxproj /p:Configuration=Release_dll /p:Platform=x64
   /p:PlatformToolset=v145` — produces `msvc/x64/Release_dll/libhunspell.dll`, exporting the full C
   API (`Hunspell_create`, `_spell`, `_suggest`, `_add`, `_remove`, `_free_list`, ... — verified via
   `dumpbin /EXPORTS`).
4. Vendored at `windows/hunspell/` (DLL + `hunspell.h` + `COPYING.LESSER`/`COPYING.MPL` for
   attribution), copied into the build output by `windows/CMakeLists.txt` the same way
   `windows/vosk/` is. **The DLL itself isn't tracked in git** — excluded by the same global `*.dll`
   rule that already excludes `libvosk.dll` — so these steps are the actual source of truth for
   regenerating it, not the repo.

**What's built:** `lib/services/hunspell_ffi.dart` — the binding itself (`Hunspell_create`/`_spell`/
`_suggest`/`_add`/`_remove`/`_destroy`; `_suggest`'s `char***` out-param maps to
`Pointer<Pointer<Pointer<Utf8>>>` in Dart FFI). `lib/services/word_tokenizer.dart` — pure word
splitter (letters + mid-word apostrophes for contractions/possessives), same "keep parsing
unit-testable" precedent as `paragraph_splitter.dart`/`mention_scanner.dart`.
`lib/services/spellcheck_dictionary_service.dart` — extracts the bundled `assets/dictionaries/en_GB/`
asset (LibreOffice dictionaries repo, LGPL, `SET UTF-8` confirmed in the `.aff` — no encoding
conversion needed) to a real file on first use, since Hunspell's C API takes file paths and can't read
inside the Flutter asset bundle. `lib/services/spell_check_service.dart` — high-level
`isCorrect`/`suggestionsFor`/`addToSessionDictionary`/`findMisspelled` wrapper.

**Editor integration:** `AnnotationHighlightController`'s single-range "speaking range" overlay
(Read Aloud) generalized to `_overlayRange` applied per-range, now also driving a
`misspelledRanges` list — a red wavy underline painted as a genuine overlay on top of whatever
annotation styling (if any) already applies, composing correctly with the speaking range too.
Recomputed on a 400ms debounce after real text changes (same guard that already distinguishes real
edits from the controller's own annotation/speaking-range notification pings). New **Spelling**
toolbar icon (badge shows the misspelled count) opens `SpellingPanel` — same
list-docked-under-the-editor pattern as `AnnotationPanel` — with suggestion chips (tap to replace
in place) and an "add to dictionary" action.

**A real bug avoided proactively, from a different angle than Read Aloud's fix:** spell check runs
*automatically* on every scene load/edit (not user-triggered like Read Aloud), so it can't be made
lazy the same way. Instead `_runSpellCheck` wraps the dictionary load in a try/catch that disables
spell check gracefully on failure (missing asset, no `path_provider` mock in the test
environment, ...) rather than crashing the rest of the editor — verified this doesn't regress any
existing widget test that builds the full `SceneEditor`.

**Two build-environment gotchas hit rebuilding after this change, both one-offs:** a transient
`INSTALL.vcxproj` failure (same flake noted in an earlier session — succeeded on immediate retry),
and a missing `build/native_assets/windows` folder that `cmake_install.cmake` expected but nothing
had created after `rm -rf build` — fixed by creating it by hand (`mkdir -p
build/native_assets/windows`) before rebuilding.

**296 tests** (was 279) — `word_tokenizer_test.dart` (7 tests) and `spell_check_service_test.dart`
(6 tests, **real end-to-end coverage against the actual vendored DLL and actual bundled
dictionary** — unlike Vosk, this is entirely offline and instant, so there's no reason to fake it),
plus 4 new `AnnotationHighlightController` tests for the generalized multi-range overlay. `flutter
analyze` clean, `flutter build windows` verified, and **the user confirmed it works live**: squiggly
underlines on real misspellings, suggestion-chip replacement, and add-to-dictionary.

**Deferred, logged in `CONSIDERATIONS.md`:** a Settings section to view/manage added-dictionary
words was requested right after this shipped — noted that it needs actual persistence built first
(`Hunspell_add` is run-time/in-memory only, per the function's own doc comment; nothing survives an
app restart yet, so there's nothing yet for a management screen to list). Also still deferred: the
per-project language/variant picker and additional downloadable dictionaries from PLAN.md (en-GB is
hardcoded as the only option for now), and the WordNet-backed thesaurus/dictionary (this phase's
other half).

---

## Phase 4.5: WordNet thesaurus/dictionary (second half)

**Built and committed 2026-07-26.** Scope decided with the user up front: SQLite asset queried via
the `sqlite3`/`sqlite3_flutter_libs` packages (not a pure-Dart index — relational lookups and future
growth room won over a smaller no-native-dep option), synonyms + definitions only for v1 (hypernym/
hyponym trees deferred), triggered from a "Look Up" entry added to the text field's own selection
context menu (right-click on Windows, the same toolbar long-press already produces on Android) rather
than a persistent docked panel.

**Data source:** Open English WordNet 2025 edition (CC BY 4.0), `english-wordnet-2025-json.zip` from
the GitHub release (`en-word.net` itself 503'd; `gh release view --repo
globalwordnet/english-wordnet 2025-edition` found the same asset directly). Base edition, not
`-plus` — the `-plus` edition adds curated proper nouns not needed for a synonym/definition lookup.

**Build pipeline:** `tool/build_wordnet_db.dart` — a one-off Dart script (using `package:sqlite3`
directly, no Flutter dependency) that reads the release zip's `entries-*.json` (word → sense →
synset-id index, 27 files, one per starting letter) and `{noun,verb,adj,adv}.*.json` (45 category
files, synset-id → definition/members/hypernym) and writes a compact `synsets`/`senses` schema:
107,519 synsets, 185,129 word-sense rows. Same "committed asset, rebuilt only when picking up a newer
release" convention as the Hunspell dictionaries — not regenerated at app-build time. Output:
`assets/wordnet/wordnet.sqlite`, 21.8 MB (dwarfs the 1.3 MB Hunspell `.dic`, but this is a full
synonym+definition graph, not a wordlist — no attempt made to shrink further since nothing else in
the app is size-constrained yet).

**Runtime:** `lib/services/wordnet_dictionary_service.dart` extracts the asset to a real file on
first use (`sqlite3` opens by path, not asset buffers — identical shape to
`SpellCheckDictionaryService`). `lib/services/thesaurus_service.dart` opens it `OpenMode.readOnly`
(a static reference dataset, never written to) and exposes `lookup(word)` → one `WordSense` per
WordNet sense (part of speech, definition, synonyms with the queried word excluded from its own
list). `posLabel()` maps WordNet's single-letter codes (`n`/`v`/`a`/`s`/`r`) to readable words —
`s` (adjective satellite) collapses to "adjective" too, since the satellite/head distinction isn't
meaningful to a novelist looking up a word.

**Editor integration:** `contextMenuBuilder` on the scene editor's `TextField` inserts a "Look Up
'word'" entry ahead of the platform's own Cut/Copy/Paste items whenever the selection is a single
word (no whitespace) — reuses Flutter's own selection-toolbar plumbing rather than a hand-rolled
right-click handler, so it works on both Windows (right-click) and Android (long-press toolbar) for
free. Renamed `_replaceMisspelled` → `_replaceRange`, a generic `[start,end)` swap-for-a-word helper
now shared by the spelling panel's suggestion chips and the new thesaurus popover's synonym chips —
both are the same operation on the same editor. `_ThesaurusPopover` (new widget, same file) shows
each sense's definition plus synonym chips (tap to replace in place); anchored to a fixed corner of
the editor Stack rather than the selection itself — same pragmatic call already made for
`_MentionSuggestions`, logged there: precise caret/selection anchoring needs `TextPainter` geometry
tuned by eye against a running window, not available this session.

**14 new tests** (`thesaurus_service_test.dart`) against the real bundled database — same rationale
as spell check's tests: entirely offline and instant, no reason to fake it. Covers lookup, case-
insensitivity, self-exclusion from its own synonym list, multi-sense words, unknown words, empty
input, `posLabel`, and extraction idempotency. **310 tests total**, `flutter analyze` clean (only
`avoid_print` infos on the one-off build script, which is expected to print progress), `flutter build
windows` verified successful with the sqlite3 native DLL bundled. **Not yet click-tested by the user**
— launched via `start ""` and handed off for a manual pass, same computer-use window-resolution
limitation as every other phase.

---

## Phase 5: Google Drive Sync

**Built and committed 2026-07-26.** One correction to PLAN.md caught before writing any code:
PLAN.md named `google_sign_in` for auth, but that package only supports Android/iOS/macOS/Web —
**not Windows** (confirmed directly against its pub.dev page). Used `googleapis_auth`'s
browser-plus-local-loopback OAuth flow (`clientViaUserConsent`) instead: it opens the system browser
to Google's consent screen and catches the redirect on a `localhost` port it starts itself — works
identically on Windows and Android, one code path for both v1 platforms instead of two. User
decisions locked in before building: SQLite-equivalent three-way diff (not a naive timestamp
comparison), and a **dedicated conflict-resolution screen**, explicitly *not* reusing Version
History's diff/restore UI (they're different kinds of divergence — cross-device vs.
same-device-over-time — even though both compare two text versions).

**OAuth client setup:** one app-level "Desktop app" OAuth client registered in Google Cloud Console
(Drive API enabled, `drive.file` scope, user's own account as a test user while unverified) — this
identifies the *app* to Google, not any individual user; every end user still signs in with their
own Google account and only ever grants the app access to files it creates itself. Client ID/secret
supplied at build time via `--dart-define-from-file=oauth_config.json` (gitignored;
`oauth_config.example.json` documents the shape) and read through
`lib/config/drive_oauth_config.dart`'s `String.fromEnvironment` constants — never hardcoded, never
committed. User's real Client ID is already in place this session; the secret field is still blank
pending the user pasting it in.

**Token storage:** `lib/services/drive_token_store.dart`. `flutter_secure_storage` was deliberately
avoided — not just the Windows ATL-component build issue already hit once for the vault signing key
(see Phase-2-era data-protection notes), but a structural problem specific to this package: adding
it as a dependency at all pulls its Windows platform implementation into every `flutter build
windows` regardless of whether Dart code on that platform ever calls it, so it would break the
Windows build even used Android-only. Windows: real encryption via DPAPI
(`CryptProtectData`/`CryptUnprotectData`, tied to the current Windows user account) — pure Win32 FFI
against `crypt32.dll`, which ships with Windows, so no native library build at all. Android: a plain
file under the app's private sandboxed storage (not additionally encrypted — logged in
CONSIDERATIONS.md as a deferred Keystore-backed hardening step, not an open door, since Android
already denies other apps access without root).

**Sync design — three-way diff against a manifest**, same shape as any offline-first sync (Dropbox,
git): `lib/models/sync_manifest.dart` (`.sync/manifest.json` per project, already scaffolded in
`LibraryService.createProject` since Phase 0) records every file's local hash + Drive fileId/md5 as
of the last successful sync. `lib/services/drive_sync_planner.dart` is **pure diff logic, no I/O at
all** — compares current local hashes, current Drive listing, and the manifest to decide
upload/download/delete-local/delete-remote/conflict per file, deliberately kept side-effect-free so
the decision logic is unit-testable without a live Drive connection. Full case breakdown documented
inline; the one nuance worth calling out here: **a deletion racing an edit is not treated as a
conflict** — whichever side still has content wins automatically (no ambiguity, no reason to make
the user choose), so the dedicated conflict screen only ever shows genuine "both sides edited it
differently" divergence.

**What's built:** `lib/services/sync_manifest_service.dart` (manifest read/write, plus hashing every
local file with md5 — matching Drive's own `md5Checksum` field so hashes compare directly — excluding
`.sync/` itself and Version History's `.history_backup/` mirror, which has no reason to double Drive
storage for purely-local corruption insurance). `lib/services/drive_remote_store.dart` —
`GoogleDriveRemoteStore` wraps `drive.DriveApi` behind a small `DriveRemoteStore` interface
(list/upload/download/delete), so `DriveSyncService` never talks to the real API directly and is
testable against `test/fake_drive_remote_store.dart`'s in-memory fake instead. One dedicated
`Narraity/` Drive folder, one subfolder per project, nested Drive folders mirroring local
subdirectories exactly (`manuscript/scenes/` becomes `manuscript` → `scenes` on Drive) since Drive
itself has no path concept, only parent-folder links; folder ids cached per sync run.
`lib/services/drive_sync_service.dart` (`DriveSyncService.sync`) applies a computed plan: uploads,
downloads, propagates deletes both directions, and — critically — **writes nothing to the manifest
for conflicting paths**, so they keep showing up as conflicts on every future sync until actually
resolved rather than the sync silently picking a side. `saveConflictCopy`/`resolveKeepRemote`/
`resolveKeepLocal` implement the three resolution actions the conflict screen offers.

**UI:** `lib/screens/drive_conflict_screen.dart` — the dedicated screen, one card per conflict with
"Keep this device" / "Keep Drive" / "Keep both" (the last one calls `saveConflictCopy` before pulling
Drive's version, so nothing is silently discarded — PLAN.md's literal requirement). Settings →
**Google Drive Sync** (`lib/widgets/drive_sync_settings_section.dart`): connect/disconnect, and once
signed in, a per-project list with a manual "Sync now" button and last-synced timestamp — opens the
conflict screen automatically if a sync run finds any. Deliberately no automatic background sync
loop this session (PLAN.md's "manual Sync Now + on-foreground background sync" — only the manual
half is wired; the on-foreground trigger is a small follow-up, not built yet).

**28 new tests**: 13 for the pure diff planner (`drive_sync_planner_test.dart` — every case in the
three-way diff, including the two "not actually a conflict" deletion-racing-an-edit cases), 6 for
manifest read/write/hashing (`sync_manifest_service_test.dart`), 9 for the full orchestration against
the fake Drive store (`drive_sync_service_test.dart` — upload, download, no-op resync, in-place
update, delete propagation, a genuine conflict left untouched, and all three resolution actions).
**332 tests total**, `flutter analyze` clean, `flutter test` all green, both `flutter build apk
--debug` and `flutter build windows` verified successful (the Windows build needed the user to
close a previous session's `narraity.exe`, which was still running and holding its own binary
locked, before it would link).

**Not click-tested end to end against real Drive** — the OAuth client secret wasn't supplied yet as
this was written, and even once it is, an actual browser-consent round trip and real file
push/pull/conflict needs the user to drive it manually (same "hand off for a manual pass" pattern as
every GUI-dependent feature in this project, compounded here by needing live Google credentials
which Claude Code cannot supply or exercise itself).

**Deferred, logged in `CONSIDERATIONS.md`:** on-foreground automatic sync trigger (manual "Sync now"
only for v1), Android Keystore-backed token encryption (currently plain-file-in-sandbox), a
side-by-side content preview on the conflict screen (currently just filenames + actions, no diff
view — Version History's diff viewer could potentially be reused for the *preview* rendering even
though the resolution UI stays separate, worth a follow-up look), and multi-account/multi-Drive
support (one signed-in account for the whole app, matching PLAN.md's scope).

---

## Phase 5 follow-up: cancellable sign-in

**Real bug found by the user on first click-through, fixed same session.** Clicking "Connect" showed
the signing-in spinner as expected, but if the browser flow never completed — closing the tab
without finishing, the consent screen just sitting there, anything short of an actual success or
thrown error — the spinner had **no way out**: `clientViaUserConsent`'s underlying future just never
resolves in that case, and there was no cancel affordance at all.

**Fix:** `DriveConnectionNotifier.connect()` now races the real sign-in attempt against a
cancellable `Completer`, added a `cancelConnect()` method, and the Settings UI shows a **Cancel**
button next to the spinner while `signingIn`. There's no way to truly abort
`clientViaUserConsent`'s local server/browser flow once started (Google's own API gives no
cancellation hook), so cancelling just stops the *UI* waiting on it — the abandoned attempt keeps
running in the background and either eventually succeeds (harmless: the next "Connect" click will
simply find it already signed in) or fails silently, with its result swallowed via
`.then(_, onError: _)` so it doesn't surface as an unhandled-future error once nobody's listening.
An identity check on the notifier's cancel-signal field guards against a stale finished attempt
clobbering a *newer* connect() call's state, in case the user cancels then immediately reconnects.

**2 new tests** (`drive_provider_test.dart`) using a `_HangingDriveAuthService` test double whose
`ensureSignedIn` never resolves until manually triggered — verifies both that `cancelConnect` resolves
a stuck `connect()` with no error message (a deliberate cancel isn't a failure), and that a genuine
failure still surfaces its error text. **334 tests total**, `flutter analyze` clean, `flutter test`
all green, `flutter build windows` verified after the user closed the previous session's running
instance. **User confirmed real end-to-end Drive sync works**: signed in via the browser flow,
`Sync now` created a real `Narraity/` folder structure in their actual Google Drive, first attempt
hit a real, expected 403 (Drive API not yet propagated after just being enabled in Google Cloud
Console — same "wait a few minutes" the API's own error message says), succeeded on retry.

---

## Phase 5 follow-up: Vault and App Settings now sync too

**User-identified gap, same session:** Drive sync only ever covered project files — the Vault
(disaster-recovery backups) and every device-preference setting (theme, dictation language,
etc.) stayed local-only, which quietly defeats the Vault's whole "survives losing this device"
purpose. Two design questions asked via AskUserQuestion up front: (1) should the Vault sync
automatically once connected, or stay opt-in — **automatically, no extra toggle**; (2) should
"app options" sync be all-or-nothing or content-only — **all of it, one consolidated file**.

**Vault sync — reused the existing sync engine outright, no new sync logic needed.**
`DriveSyncService.sync(Directory, String folderName)` was already generic (built that way from the
start, not retrofitted) — syncing the Vault is just another call to it, `service.sync(vaultRootDir,
'_Vault')`, exactly like a project. `LibraryService.listProjects` already skips `_`-prefixed folders,
so `_Vault` was never at risk of appearing as a fake "project."

**App Settings sync — new `lib/services/app_settings_service.dart`.** Consolidates every
device-preference `SharedPreferences` key into one `_Settings/settings.json` (new reserved folder,
same `_`-prefix-skipped-by-LibraryService pattern as `_Vault/`): `exportToFile()` snapshots current
values before a sync runs, `importFromFile()` re-applies them after (in case Drive pulled a newer
file from another device). **Deliberately scoped to genuine app-wide options** — theme, dictation
language/model-size *preference* (not the downloaded model itself, still per-device), spell check
on/off, Read Aloud voice/rate/pitch, editor font, vault retention count/auto-refresh — and
**deliberately excludes Reference Panel visibility/width/pins**, which are already-documented
machine workspace state (see Phase 2.5's notes on why pins live in `SharedPreferences` keyed by
project id, kept out of the project folder on purpose) rather than "app options."

**Real gap found while scoping this: the spell-check on/off toggle was never actually persisted at
all** — `spellCheckEnabledProvider` was a plain `StateProvider<bool>((ref) => true)` with no
`SharedPreferences` read/write anywhere, so it silently reset to "on" every launch regardless of
what a user chose (moot until now, since nothing in the UI even sets it yet either — but it needed
real persistence to be worth including in the settings sync at all). Converted to the same
restore/`Notifier` pattern every other persisted setting in this codebase already uses.

**UI:** Settings → Google Drive Sync gained two always-present rows above the project list —
"Vault backups" and "App settings" — sharing the exact same manual "Sync now"/last-synced/conflict
flow as projects. Generalized `_ProjectSyncTile` → `_SyncTargetTile` (title/icon/folder-name/
directory-resolver instead of a hard-coded `Project`) since three different kinds of target now
need identical sync/status/conflict-navigation behavior — same "worth sharing on the third
consumer" threshold as `sceneColumnsProvider`'s and `ImmediateDragRecognizer`'s earlier moves to
shared homes. `DriveConflictScreen` generalized the same way (`title`/`folderName`/`directory`
instead of a `Project`), since conflicts can now come from any of the three targets.

**9 new tests**: 6 for `AppSettingsService` (export scoping, round-trip, no-op on missing file,
corrupt-file resilience, and an explicit assertion that Reference Panel state is never exported),
3 for the spell-check persistence fix (default, persists, a fresh instance restores it — directly
reproducing the "resets every launch" bug as a regression test). **343 tests total**, `flutter
analyze` clean, `flutter test` all green. `flutter build windows` pending — the user had the app
open again when this was written; needs a rebuild + a real click-through (connect already verified
working, but Vault/Settings sync entries themselves are new and unverified by eye).

**Deferred, logged in CONSIDERATIONS.md:** conflict handling for the settings file itself works
identically to any other synced file (three-way diff, dedicated conflict screen if two devices
changed different settings between syncs) — not specially handled, and not yet exercised with two
real devices to confirm the merge story is as painless in practice as it is on paper.

---

## Phase 5 follow-up: automatic sync (immediate per-file, daily, and frequent)

**User asked for three things after confirming manual sync worked end to end:** an immediate sync
right after a file saves (just that one file, not a full project re-diff), a periodic full sync +
reconciliation check, and a log so "is this actually syncing?" has a concrete answer. Two
AskUserQuestion rounds up front: change detection via a **filesystem watcher** (not hooking every
save path individually — one watch catches scenes, characters, todos, goals, plot grid, timeline,
relationships, annotations, all of it, with no per-service wiring); immediate sync **off by
default** (new automatic network activity); periodic sync as **two independent, user-configurable
timers** — a "daily" checkbox plus a "more frequent" dropdown (off/5/15/30/60 min), not a single
fixed interval.

**Single-file targeted sync — new capability, not a hack around the full sync.**
`DriveRemoteStore.findFile()` does one targeted Drive query for a single file (resolving only that
file's own folder chain, not creating anything that doesn't already exist) instead of
`listFiles()`'s full recursive walk — the whole point of "immediately after saving" is staying cheap
regardless of project size. `DriveSyncService.syncSingleFile()` reuses the exact same
`DriveSyncPlanner` the full sync uses, but scoped to a manifest containing *only* that one path
before diffing — passing the whole manifest here would make every other tracked file look
deleted-on-both-sides, since only one path's local/remote state was actually fetched. Refactored the
shared "apply a plan to disk + Drive" logic out of `sync()` into `_applyPlan()` so both paths share
it instead of duplicating upload/download/delete handling.

**`lib/services/project_file_watcher.dart`** wraps `Directory.watch(recursive: true)`, debounced
per relative path (2s default), with the same `.sync`/`.history_backup` exclusions as
`SyncManifestService.hashLocalFiles`. Its injectable event type (`ProjectFileChangeEvent`) is a
small custom class, not `dart:io`'s own `FileSystemEvent` — that class is `sealed` with no public
constructor, so tests couldn't build synthetic events against the real type at all; wrapping it was
the only way to get deterministic, timing-independent debounce tests.

**`lib/state/drive_auto_sync_provider.dart`** ties it together: three persisted toggles
(immediate/daily/frequent-minutes, all following the same restore/`Notifier` pattern as every other
setting in this codebase), a `DriveAutoSyncScheduler` owning two independent `Timer.periodic`s
(rescheduled via `ref.listen` whenever the settings or connection status change), and
`projectFileWatcherProvider` — a `FutureProvider.autoDispose` that only constructs a watcher while a
project is open, immediate sync is on, and Drive is connected, relying on Riverpod's normal
watch-triggers-rebuild-disposes-old-instance semantics to start/stop cleanly as any of those three
conditions change. The scheduler is kept alive for the whole app session via `ref.watch` in
`NarraityApp`'s root build method (timers need to run regardless of which screen is open); the
watcher is mounted from `ProjectShellScreen` instead, since it's only meaningful while a project
is actually open.

**`lib/services/drive_sync_log_service.dart` + `lib/models/sync_log_entry.dart`**: a local, capped
(200 entries) activity log — every manual, immediate, or periodic sync attempt appends one entry
(target, trigger kind, action counts, conflicts, or an error). Deliberately stored under the app
support directory (same as `DriveTokenStore`), **not** under `Documents/Narraity/` — putting it
there would mean the App Settings sync target picks up and starts syncing the log itself, which is
per-device diagnostic information with no business being on Drive. New **Sync Log** screen
(read-only list, newest first, clear action) reachable from Settings → Google Drive Sync.

**The three auto-sync toggles are themselves included in the App Settings sync** — restoring "how
you set the app up" on a new device now includes whether you'd turned on immediate/daily/frequent
sync there too, consistent with the whole point of that feature.

**UI:** Settings → Google Drive Sync gained an "Automatic Sync" card (three controls) and a "Sync
Log" link, both above the existing project/Vault/Settings sync-target list.

**19 new tests**: 5 for `syncSingleFile` (including the key regression — a single-file sync must
never disturb unrelated manifest entries), 7 for `ProjectFileWatcher`'s debounce/filter logic, 6 for
`DriveSyncLogService` (round-trip, capping, corrupt-file resilience), 6 for the three persisted
toggles, plus 1 more for `AppSettingsService` covering the new sync-related keys. **368 tests
total**, `flutter analyze` clean, all green, `flutter build windows` verified successful. **Not yet
click-tested** — the watcher/scheduler/log are new this session; the underlying sync engine they
call is already real-Drive-verified, but the automatic triggering itself hasn't been observed live.

**Deferred, logged in CONSIDERATIONS.md:** no visible "syncing now" indicator outside the Settings
screen itself (the Sync Log is the only visibility so far — a persistent status icon in the app
shell was discussed as a possible follow-up but not built this session); the frequent-sync interval
list is a fixed preset (5/15/30/60 min), not free-form; no coalescing if a periodic tick and an
immediate per-file sync land on the same project at the same moment (harmless — worst case is two
sequential syncs where the second is a no-op — but not explicitly deduplicated).

---

## Publishing: GitHub repo, signed MSIX, CI, v1.0.0 release

**Repo:** public, [github.com/anubisalpha/narraity](https://github.com/anubisalpha/narraity), all
rights reserved (no OSS license — public for visibility, not reuse). Windows only for now, no
Android artifact published per explicit user decision.

**Real bug found and fixed before anything could even build elsewhere:** BUILD_LOG had repeatedly
described the vendored Hunspell/Vosk DLLs as "checked in," but they were never actually tracked — a
machine-wide `*.dll` rule in this developer's **global** gitignore
(`C:\Users\marca\Documents\gitignore_global.txt`) silently excluded every DLL from every commit in
every repo on this machine. Fixed with explicit negation patterns in the repo's own `.gitignore`
(`!windows/hunspell/*.dll`, `!windows/vosk/*.dll`) and committed the real ~53MB of vendored
binaries — without them, nobody (including CI) could build or test the app at all. Worth checking
for in any *other* project on this machine that also claims to vendor binaries.

**MSIX packaging — the `msix` pub package's own bundled MakeAppx.exe/signtool.exe are broken on
this machine.** Both fail with a WinSxS "side-by-side configuration is incorrect" error — a version
mismatch between the frozen toolkit binaries the package ships and what's actually installed (same
class of issue as the earlier Flutter/VS-2026 SDK-recognition patch). Worked around by using the
real Windows SDK's own matched `makeappx.exe`/`signtool.exe` directly
(`C:\Program Files (x86)\Windows Kits\10\bin\<version>\x64\`) — scripted in
`windows/build_msix.ps1`, invoked via PowerShell specifically (Bash's backslash-escaping mangled
the native exe's Windows-style path arguments beyond recognition).

**Self-signed certificate for now** (user's choice — a CA-issued one is a separate paid/verified
purchase, not something scriptable). Generated via `New-SelfSignedCertificate`, subject `CN=Anubis
Productions` matching `pubspec.yaml`'s `msix_config.publisher` (must match exactly, or Windows
rejects the package — the `msix` tool actually auto-overwrites a mismatched `publisher` config value
with whatever certificate's subject is configured, once one is set via `certificate_path`).
Public half exported as `narraity_public.cer` (safe to distribute, no private key) so installers can
import-and-trust it; the `.pfx` itself stays local, gitignored. **Did not attempt to install the
certificate into any trust store myself** (even `CurrentUser`) — that's a system/security-settings
change, which is the end user's own step to take, not something to automate on someone's behalf.

**CI (`.github/workflows/ci.yml`) runs on `windows-latest`, not the cheaper `ubuntu-latest`** — the
test suite loads real vendored native DLLs via `dart:ffi`, which only exist as Windows binaries.
Real gotcha hit immediately: `flutter analyze`'s exit code doesn't distinguish severity — 5
info-level `avoid_print` lints on the one-off WordNet build tool (expected; it's a CLI tool that's
supposed to print progress) were enough to fail the whole CI job, even though the text output
"looked clean" when read locally. Fixed with `// ignore_for_file: avoid_print` on that one file.

**About screen** (Settings → About): version via `package_info_plus`, license notice, third-party
attributions (Hunspell, Vosk, Open English WordNet).

**README split**: user feedback mid-session — someone landing on the repo to download and install
the app doesn't need build/OAuth-setup/MSIX-signing instructions before they reach a download link.
Moved all of that into `DEVELOPMENT.md`; README now leads with what the app is, a Download section,
and a License section, with feature descriptions after. Also copied `PLAN.md` into the repo itself
(the README used to link to it via a relative path that only resolved on the original dev machine,
outside the actual git repo — a dead link for anyone who'd cloned the public repo).

**Published as [v1.0.0](https://github.com/anubisalpha/narraity/releases/tag/v1.0.0)** — signed
`narraity.msix` + `narraity_public.cer` attached, release notes covering the install steps and a
feature summary.

---

## Phase 6: General export (PDF, DOCX, EPUB, plain text)

**Built and committed 2026-07-26.** PLAN.md's general-export scope (PDF, DOCX, plain text) plus
EPUB (originally scoped under Phase 6.3's KDP ebook path) — all four picked to build in one pass,
per user's own priority call. The KDP-specific print path (trim size presets, margin/gutter
calculation, running headers, wraparound cover with spine calc) is deliberately **not** part of this
pass — that needs its own dedicated UI and is a distinct enough sub-feature to scope separately
later.

**Shared plumbing, built first so every format reuses it rather than re-deriving its own copy:**
- `lib/services/export/manuscript_outline_builder.dart` — flattens the manuscript tree (front
  matter, arbitrarily nested nodes, back matter) into reading order with each section's nesting
  depth, pure and synchronous (content is read separately, lazily, per format).
- `lib/services/export/markdown_lite.dart` — parses the scene editor's markdown-subset formatting
  (`**bold**`, `*italic*`, `~~strikethrough~~`, `## heading`, `> quote`, `***` scene break) into a
  block/run structure (`MdBlock`/`MdRun`). Deliberately preserves a writer's own literal line
  breaks within a paragraph rather than collapsing them into one run-on line or one block per line —
  the scene editor is a plain multi-line text field, not a rich-paragraph editor, so a writer's own
  formatting choice (dialogue lines, verse) is real signal, not incidental whitespace.

**Plain text** (`txt_exporter.dart`) strips every marker down to bare prose — PLAN.md's explicit
"stripped-down option," with the export UI showing an explicit warning dialog (images/formatting
are dropped) before proceeding, exactly as specified.

**DOCX and EPUB are both hand-rolled directly** (`docx_exporter.dart`, `epub_exporter.dart`) via the
`archive` package already used elsewhere in this project — no mature pure-Dart writer exists for
either format on pub.dev, the same situation Hunspell/Vosk were in. Both are just ZIP archives of
XML/XHTML parts:
- **DOCX** uses direct paragraph/run formatting (bold, size, indentation) rather than named styles,
  so it needs no `word/styles.xml` at all — fewer moving parts to get wrong without a copy of Word
  on hand to verify against directly. Verified with a real XML parser (`XmlDocument.parse`) against
  a manuscript exercising every block type, confirming both well-formedness and that escaping
  round-trips correctly (`Tom & Jerry < 5 > 0` survives `&amp;`/`&lt;`/`&gt;` and back).
  A newly-added `xml` package dev dependency (already present transitively) makes this direct
  well-formedness check possible.
- **EPUB** builds an EPUB3 package: an uncompressed `mimetype` entry (must be the *first* zip
  entry, stored not deflated, per the EPUB spec — the `archive` package's per-file
  `CompressionType.none` made this straightforward), a nav document doubling as the in-app
  Automatic TOC's export counterpart, and one XHTML file per manuscript section. Verified the same
  way as DOCX (real XML parser over every part) plus a check that `mimetype` really is first and
  really is uncompressed.

**PDF** (`pdf_exporter.dart`) is the one format with a genuinely mature pure-Dart library to lean
on — the `pdf` package. `MultiPage`'s `maxPages` raised from its default of 20 to accommodate a full
novel's page count. Verified via magic-header/EOF-trailer checks (no PDF-parsing library was
available to inspect content directly) plus a manuscript exercising every block type without
throwing. One informational limitation surfaced during testing: the default Helvetica/WinAnsi base
font has no full Unicode support (a `pdf` package warning, not an error) — fine for English
prose/punctuation, but non-Latin scripts would need a real embedded font, not built this session.

**UI:** `lib/screens/export_screen.dart`, reachable from a new "Export" toolbar icon in the project
shell (same icon-button pattern as Goals/Plot Grid/Timeline/Relationships/Review). A `RadioGroup`-
based format picker (PDF/DOCX/EPUB/plain text, each with a one-line description), a native
"Save As" dialog via `file_picker`, and the plain-text confirmation warning. Real gotcha hit while
building this: `RadioListTile`'s `groupValue`/`onChanged` are deprecated as of Flutter 3.32 in favor
of a `RadioGroup` ancestor widget — an info-level deprecation that would have failed CI the same way
the WordNet build tool's `avoid_print` infos did earlier this project (flutter analyze's exit code
doesn't distinguish severity), so it was migrated properly rather than suppressed.

**37 new tests** across the outline builder, markdown parser, and all four exporters — including
structural verification (zip contents, XML well-formedness, PDF magic bytes) rather than just
"didn't throw," since none of DOCX/PDF/EPUB can be opened by their real target applications on this
machine to eye-check by hand. **406 tests total**, `flutter analyze` clean, all green, `flutter
build windows` verified successful. **Not yet click-tested with real reader software** — exported
files haven't been opened in actual Word/a PDF viewer/an e-reader yet to confirm they render as
expected, only that they're structurally valid per the tests above.

**Deferred, not built this session:** the KDP print/ebook path (Phase 6.3 — trim size presets,
margin/gutter calculation, running headers, wraparound cover with spine calc), embedding cover/
in-book images in any export format (none of the four touch images at all yet — a real gap, since
Character/World profiles support images), embedding a real Unicode font for the PDF path, and an
`export-profile.json` for reusable per-project export presets (PLAN.md's data model sketch for this
exists but nothing reads/writes it yet).

---

## Current status

**Phases 0 through 5 are fully built (including both Drive sync follow-ups — Vault/App Settings
sync, and automatic immediate/daily/frequent sync with an activity log), the app is published**
(github.com/anubisalpha/narraity, v1.0.0, signed MSIX), **and Phase 6's general export (PDF, DOCX,
EPUB, plain text) is now built too.** Manuscript editor, dictation, goals, version history, data
protection and its UI, characters/worldbuilding/notes, the Reference Panel, the Plot Grid, the
Timeline, the Relationship Diagram, Phase 4's annotations/AI review round-trip/Read Aloud,
Hunspell-backed spell check, the WordNet-backed thesaurus/dictionary, Google Drive sync (projects +
Vault + Settings, manual/immediate/scheduled), and now four export formats. **406 automated tests
passing, `flutter analyze` clean, `flutter build windows` and `flutter build apk --debug` both
verified during the session.**

Commits: `3097c4b` (Phases 0/0.5/1), `bd27566` (dictation, goals, version history, manuscript
generalization), `8416beb` (data protection services), `62d1baf` (docs), `8d414ac` (data-protection
UI), `0dbb050` (Phase 2), `da76ed4` (Phase 2.5), `3f1e79b` (reference-card id-guess fix), `7466997`
(Phase 3), `d8481f5` (Phase 3.5), `8adcd8a`/`cdaab87`/`a9cc096`/`502f68d`/`1e7abc7` (Phase 4),
`a43ee44` (Phase 4.5 spell check), `577f336` (Phase 4.5 WordNet thesaurus), `8acefc1` (Phase 5 Drive
sync), `5f46024` (cancellable sign-in fix), `f819596` (Vault/App-Settings sync), `8357eba`
(automatic sync), publishing commits through `7b7f22b`, plus this session's TXT/DOCX/PDF/EPUB export
commits (see above).

**All three Phase 3/3.5 screens (Plot Grid, Relationship Diagram, Timeline) have now had a real
GUI/gesture pass.** Two genuine bugs were found and fixed on the first two (Plot Grid's zero-height
rows, Relationship Diagram's gesture-arena conflict) before Timeline was built — Timeline's canvas
reused the already-fixed drag technique from the start, so it didn't need its own bug-finding pass in
the same way, though it's only been exercised by the user for the reorder/stagger request above, not
exhaustively.

**Every Phase 4 sub-feature has now had a real click-through by the user, not just automated
tests.** Editor-facing pieces (highlight rendering, the annotations panel) — two bugs found/fixed.
The full author/reviewer round-trip — exported a scene, reviewed it in the standalone tool, added a
comment, exported comments, re-imported — worked cleanly. Read Aloud — reading from the caret, live
highlighting, and settings all confirmed working. Session persistence across an app restart and the
metadata header's exact visual polish are the only Phase 4 pieces still unconfirmed by eye.

**Spell check (Hunspell, en-GB) and Google Drive's core connect/sync/conflict flow are both
click-through verified against real Drive; the WordNet thesaurus/dictionary, the Vault/App Settings
sync targets, the automatic-sync machinery, and the new export formats are all built but not yet
click-tested** (export in particular hasn't been opened in real Word/PDF-viewer/e-reader software
yet, only verified structurally). Phase 4.5 is otherwise fully scoped per `PLAN.md` except the
deferred multi-language/variant picker for spell check, hypernym/hyponym trees for the thesaurus,
and additional downloadable dictionaries.

Still outstanding: scene-level `linkedReferences` (the fourth Reference Panel trigger from PLAN.md —
mentions, pins, and auto-detect cover the other three), per-project vault passwords, the KDP
print/ebook export path (Phase 6.3), image embedding in any export format, and Play Store readiness
(privacy policy, data safety form, plus now the Drive `drive.file` scope's data-safety disclosure).
The Plot Grid's dangling-point cleanup and the Relationship Diagram's dangling-edge cleanup on
character delete, both listed as outstanding above, were fixed in a later session — see this file's
"Bug fixes" section further down. See `CONSIDERATIONS.md` for the full list of open design
questions.

---

## Manuscript importer (DOCX, plain text/Markdown, Dabble JSON)

Import into either a new project or (behind two separate confirmation dialogs — replacing is
destructive, since it cascades through `ManuscriptService.deleteSceneFile` and drops the replaced
scenes' own Version History) an existing project. Entry point: Library screen's "Import Manuscript"
toolbar icon.

- `lib/services/import/import_tree_builder.dart` — a shared depth-stack tree builder (headings nest
  arbitrarily deep, not a fixed Chapter/Scene shape) used by both the DOCX and plain-text importers.
- `lib/services/import/docx_importer.dart` — reads real OOXML via `package:xml` (moved from a
  dev-only dependency to a real one this session). Detects headings via Word's own styleId
  convention (`Heading1`..`Heading9`, `Title`/`Subtitle` — unlocalized ids even though the display
  name is), plus a bold+font-size fallback for direct-formatted documents — needed so Narraity's own
  DOCX export (direct formatting, not named styles) round-trips through reimport. A real
  export-then-reimport test caught the title page being misdetected as a phantom chapter, fixed by
  also requiring the fallback heuristic's paragraph not be centered.
- `lib/services/import/dabble_json_importer.dart` — schema verified against 5 real Dabble exports.
  A real per-project export is `{docId, state: {id, type:"novel", docs: {...}}}`; a different
  full-account-backup format (`{dabble:{...}, patches:[...]}`) is explicitly rejected with a clear
  error rather than mis-parsed. Scene prose is a Quill Delta — `bold`/`italic`/`strike` map to
  Narraity's `**`/`*`/`~~`, `blockquote` maps to `> `, `list` (no Narraity equivalent) becomes a
  plain `-`/`N.` prefix rather than being silently dropped. Quill's `{"br": true}` embed is always
  immediately followed by the real `"\n"` in practice, so `br` is skipped and only `\n` flushes a
  line — treating both as separate breaks would double every paragraph gap. Trashed/deleted content
  is never referenced by a live book/chapter's own `children`, so a plain top-down walk from
  `manuscripts` naturally excludes it.
- `lib/services/import/manuscript_importer.dart` — the shared entry point (`parseFile`,
  `suggestedTitle`, `materializeInto`, `clearExistingManuscript`) all three format-specific
  importers above sit behind; `lib/widgets/import_destination_dialog.dart` is the "new project vs.
  replace an existing one" picker UI.

## In-app update checker + Windows auto-update

Two independent pieces:
- **In-app checker** (`lib/services/update_check_service.dart`) hits GitHub's `releases/latest` API
  and compares `tag_name` against the running version — a manual "Check for Updates" button in
  Settings → About, plus a silent session-cached startup check showing a dismissible
  `MaterialBanner` (`lib/widgets/update_available_banner.dart`) on the Library screen. Never
  installs anything itself, just links out.
- **Real Windows auto-update via `.appinstaller`** (`windows/build_appinstaller.ps1`) — Windows'
  native sideloaded-MSIX update mechanism. Opted into at *install* time by choosing README's
  "Option B" instead of the plain `.msix` (a distribution/install-time choice, not an in-app
  toggle). `ShowPrompt="true"` — every update needs the user's confirmation, never silent. Both the
  `.appinstaller` and the `.msix` it points to must be published at GitHub's stable
  `releases/latest/download/...` URLs, not version-pinned tag URLs, since Windows re-fetches the
  `.appinstaller` from wherever it was originally installed from.
- `windows/release.ps1 -Version X.Y.Z` — the maintainer release script: bumps both `pubspec.yaml`'s
  `version:` and `msix_config.msix_version` (Windows compares the latter's 4-part number for the
  `.appinstaller` path — independent fields, easy to forget one), runs analyze+test as a gate,
  builds/signs the MSIX, generates the `.appinstaller`, commits, tags, pushes, and runs
  `gh release create` with all three assets attached.
- Gotchas hit: `pubspec.yaml` is CRLF, so the version-bump regex needed a `(?=\r?$)` lookahead
  rather than consuming `\r?$` directly (which would flip that one line to LF on replace).
  PowerShell-generated XML comments containing `--` (a prose dash) are invalid per the XML spec and
  broke parsing — caught by actually parsing the generated `.appinstaller` as XML, not eyeballing
  it. **Neither script has been run for a real release yet** — validated via dry-run regex tests and
  a scratch-directory XML-generation test only.

---

## Bug fix: `FilePicker.saveFile()` hung forever on Windows (GitHub issue #1)

Root cause: `file_picker`'s Windows `saveFile` runs the native `GetSaveFileNameW` call inside a
**spawned isolate**, then the main isolate `await`s a result port. `_instantiateOpenFileNameW`
validates the *default filename* and throws `IllegalCharacterInFileNameException` if it contains a
Windows-reserved character (`< > : " / \ | ? *`) — but that throw happens inside the spawned
isolate, where Dart's default behavior for an uncaught isolate error is to print to stderr and kill
*only that isolate*, never propagating to the caller's `try/catch` or `AppLogger`. Nothing is ever
sent through the port, so the main isolate's `await` hangs forever — no exception caught, no log
entry, process stays responsive but parked. The trigger case: a project titled `"Book 1: Wisdom of
the Elders"` (a `:`) being exported.

Fixed with a shared `lib/services/filename_sanitizer.dart` (`sanitizeFileName`) — strips the
Windows-reserved character set, trims, falls back to `Untitled` — used everywhere a title becomes a
filesystem name: `export_screen.dart`, `review_export_screen.dart`,
`review_session_detail_screen.dart`'s `FilePicker.saveFile` calls, and `library_service.dart`'s
project-folder naming (which had its own inline copy of the same regex before this session; now a
single canonical policy). Verified live via `flutter run -d windows` against the actual hang case;
issue closed on GitHub with a summary of the root cause.

## PDF/EPUB export overhaul

Several real, independent defects found while live-testing exports against "Book 1: Wisdom of the
Elders" (a real ~20-chapter manuscript) and a reference EPUB from Kindle Create:

- **PDF: any paragraph taller than one page crashed the whole export.** Paragraphs were wrapped in
  `pw.Padding` (a `SingleChildWidget`, not splittable across pages like `pw.RichText`/`pw.Text`
  are), *and* `pw.RichText`'s own `canSpan` only returns true when `overflow: TextOverflow.span` is
  set explicitly (the package's default is `visible`, which doesn't span) — both conditions had to
  be fixed. A whole chapter written as one continuous block of prose (no blank lines) is exactly the
  real-world shape that triggers this.
- **PDF: smart quotes/dashes/ellipsis rendered as missing-glyph boxes.** The `pdf` package's default
  base-14 Helvetica font has no glyphs outside WinAnsi Latin-1. Normalized the small set of
  typographic characters a word processor (or this app's own text) produces to their closest ASCII
  equivalent for the PDF path specifically (`_pdfSafeText` in `pdf_exporter.dart`) — a real Unicode
  embedded font remains a `CONSIDERATIONS.md` item for full fidelity.
- **PDF/DOCX: only depth-0 sections forced a page break.** A book structured as a single top-level
  "Book" node wrapping many "Chapter" children (all depth 1) — which is exactly what a real writer
  produces, and what the Dabble importer's schema naturally yields too — got exactly one page break
  total (after the title page), none between chapters. Fixed by making "chapter boundary"
  depth-independent: it now also fires on freeform `typeLabel`s reading as chapter/act/book/part
  (`ManuscriptOutlineBuilder._chapterLikeLabels`), covering every shape `manuscript_seeds.dart`
  offers. DOCX had *no* page-break logic between sections at all before this fix.
  New `ExportSection.startsNewPage` field carries this rule to every format from one place.
- **EPUB: every Scene got its own spine file**, not just every Chapter — a 20-chapter, ~5-scene
  book produced 66 separate reader-visible "pages" even though scene headings are hidden by
  default. Sections are now grouped into one file per chapter boundary
  (`_EpubSectionGroup`/`_groupXhtml` in `epub_exporter.dart`); non-boundary sections merge into the
  enclosing chapter's file.
- **EPUB: no stylesheet at all**, relying entirely on reader defaults — found by diffing against a
  real Kindle Create export. Added `OEBPS/styles.css` (linked from every file): centered/uppercase
  chapter headings, first-line-indented body paragraphs with zero paragraph margin (continuous
  book-style flow), and a no-indent rule for each chapter's first paragraph (traditional
  typesetting, matching the reference export). Also fixed scene breaks, which rendered as a bare,
  textless `<hr/>` — now visible `* * *` text, matching every other export format.
- **New: per-section "print title in exports" toggle** (`ManuscriptNode.showTitleInExport`, default
  `true`) — right-click any tree section for a checked menu item. Solves the case of an imported
  book's top-level node duplicating the project's own title on the very next line after the title
  page; threaded through `ExportSection.showTitle` to all four formats (EPUB keeps the hidden
  title in `<head><title>`/the TOC for reader-chrome/navigation purposes, only the in-page `<h1>`
  is suppressed).

25 new/updated tests across `pdf_exporter_test.dart`, `docx_exporter_test.dart`,
`epub_exporter_test.dart`, `manuscript_outline_builder_test.dart`, and
`filename_sanitizer_test.dart` — including a page-object-counting proxy for PDF (content streams
are compressed, so exact page count is verified via a raw `/Type /Page` regex scan rather than a
real PDF parser dependency).

## Series, front cover images, and drag-and-drop library reordering

- **Series** (`lib/models/series.dart`, `lib/services/series_service.dart`) — a named grouping of
  projects, stored as `_Series/series-<id>.json` at the library root (same reserved-folder
  convention as `_GlobalIdeas/`/`_ReviewSessions/`; `LibraryService.listProjects()` already skips
  `_`-prefixed folders, so no scanning change was needed). Membership lives on `Project.seriesId`,
  not on the series itself — deleting a series never deletes its projects, just leaves `seriesId`
  dangling, which the library grid treats as standalone again. Library screen shows a series as
  three offset stacked cards (`_SeriesStackCard`); opening it pushes `SeriesDetailScreen` (rename,
  delete, add a new project directly into it, remove a member back to standalone).
- **Front cover images** (`Project.coverImagePath`, `LibraryService.setCoverImage`/
  `removeCoverImage`) — one cover per project, copied into `assets/covers/cover.<ext>` (replacing
  any previous file, including a stale one with a different extension). Set from a persistent row
  above front matter in the manuscript tree (not folded into the "+Front/back matter" menu, since a
  cover is a single image file per project, not a repeatable prose section backed by its own scene
  file). Shows as a thumbnail on that project's library card, and on a series' stack card (using its
  most-recently-modified member with a cover set).
- **Drag-and-drop reordering** (`Project.sortOrder`/`Series.sortOrder`) — both the top-level library
  grid and a series' own project grid. Manually-ordered items always sort first, by explicit
  position; anything never dragged falls in after, by recency — so a freshly created project still
  surfaces near the top without needing an order value of its own. `sortOrder` is a separate
  numbering per grid (a series' internal order doesn't share a namespace with the top-level grid's).
  Implemented by hand with `Draggable`/`DragTarget` rather than a `reorderable_grid_view`-style
  package dependency, since Flutter has no built-in reorderable *grid* (only `ReorderableListView`,
  single-column).

19 new/updated tests across `library_service_test.dart` and `series_service_test.dart` covering
`seriesId`/`coverImagePath`/`sortOrder` persistence and edge cases (0 is a valid `sortOrder`, not
"unset"; replacing a cover with a different extension removes the stale file). The drag gesture
itself isn't covered by an automated test — Flutter's `Draggable`/`DragTarget` interaction is
notoriously fiddly to simulate reliably in `flutter_test`, so this was verified live instead via
`flutter run -d windows`.

**465 tests total**, `flutter analyze` clean.

## Bug fixes: dangling data on delete, missing settings toggles, dictionary persistence

Four items that had been sitting in `BUILD_LOG.md`/`CONSIDERATIONS.md` as known gaps:

- **Plot Grid dangling points.** `ManuscriptService.deleteSceneFile` already cascaded to drop
  annotations anchored to a deleted scene; it now also drops any `PlotPoint` whose `sceneId`
  matches, via `PlotGridService`. Previously an orphaned point sat in `plotpoints.json` forever,
  referencing a scene id nothing could resolve — invisible in the grid, never cleaned up.
- **Relationship Diagram dangling edges.** `ProfileService.delete` (character kind only) now drops
  every `Relationship` touching the deleted character and its `layout.json` position via
  `RelationshipService.deleteRelationship`/`removeNodePosition` — the latter already existed but
  was never actually called from anywhere.
- **Spell check / thesaurus Settings toggles.** `_SettingsCategory.spellCheck` was wired as a
  "coming soon" placeholder even though `spellCheckEnabledProvider` already persisted correctly
  (fixed in an earlier session) — there was just no real UI control for it. Built the real section
  with a working switch, plus a **new `thesaurusEnabledProvider`** (mirrors the spell-check one
  exactly) gating the "Look Up" context-menu item, which had no on/off control at all before this.
  Both sync via the existing `AppSettingsService`/Drive app-settings sync (`spellCheck.enabled` /
  new `thesaurus.enabled` keys).
- **"Add to Dictionary" persistence.** `Hunspell_add` only ever touched the in-memory run-time
  dictionary (`hunspell_ffi.dart`'s own doc comment already flagged this) — nothing survived an app
  restart. New `CustomDictionaryService` persists to `_Settings/custom-words-<languageTag>.txt`
  (app-wide, not per-project, same reserved-folder convention as `_GlobalIdeas/`), replayed through
  `Hunspell_add` when `SpellCheckService.load` runs. Also added a small management list to the new
  Spell Check settings section (view/remove persisted words) using `Hunspell_remove` — already
  FFI-bound in `hunspell_ffi.dart` but unused anywhere until now.

19 new/updated tests, including one that reproduces the actual persistence bug directly: add a
word, load a **second, independent** `SpellCheckService` instance, and confirm the word is still
recognized — the failure mode a fresh-launch scenario would hit.

**481 tests total**, `flutter analyze` clean.

## v1.0.1 — first real release cut via release.ps1

Previously `release.ps1`/`build_msix.ps1`/`build_appinstaller.ps1` had only been dry-run tested
(regex/XML-generation tests, never actually executed for a real release — see the Manuscript
importer / update-checker session's notes). This session ran the real thing for the first time and
hit three genuine environment gaps, now fixed and documented in `DEVELOPMENT.md`'s MSIX section:
missing `nuget.exe` (a release-mode-only dependency of `flutter_tts`'s Windows CMake build — debug
builds never touch it, which is why nothing surfaced it all session), a stale `CMAKE_INSTALL_PREFIX`
left over from an earlier debug build's cache pointing at `C:\Program Files\narraity` (needs admin),
and `flutter build windows --release` expecting `build/native_assets/windows/` to already exist.
`release.ps1` itself needed no code changes — every gap was environment/tooling, not the script's
own logic — but `flutter analyze`/`flutter test` (the script's built-in sanity gate) hit a
transient file-lock on `pubspec.yaml`/`build\unit_test_assets` when run through it specifically;
worked around by running the version bump and analyze/test manually outside the script, then
resuming from the MSIX build step.

**v1.0.1 published**: github.com/anubisalpha/narraity/releases/tag/v1.0.1 — `narraity.msix`,
`narraity_public.cer`, `narraity.appinstaller` all attached. This is also the first release the
in-app "Check for Updates" checker and the `.appinstaller` auto-update path have anything real to
find, since both only ever see releases published this way.
