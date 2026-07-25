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

## Current status

Phases 0 through 2.5 are built and verified: manuscript editor, dictation, goals, version history,
data protection and its UI, characters/worldbuilding/notes, and the Reference Panel. 169 automated
tests passing, `flutter analyze` clean, both `flutter build windows` and `flutter build apk --debug`
succeed. Commits: `3097c4b` (Phases 0/0.5/1), `bd27566` (dictation, goals, version history, manuscript
generalization), `8416beb` (data protection services), `62d1baf` (docs), `8d414ac` (data-protection
UI), `0dbb050` (Phase 2).

Next per `PLAN.md`: **Phase 3** (Plot Grid, Timeline, relationship diagram) or **Phase 4** (comments,
highlights, sticky notes, footnotes on a shared text-anchor mechanism, plus the AI/external review
round-trip). Worth noting Phase 4's anchor mechanism is the same machinery a rich-text editor would
need to render `[[…]]` mentions as chips, so pairing them is sensible.

Still outstanding from earlier phases: scene-level `linkedReferences` (the fourth Reference Panel
trigger from PLAN.md — mentions, pins, and auto-detect cover the other three), per-project vault
passwords, export format priority, and Play Store readiness (privacy policy, data safety form).
