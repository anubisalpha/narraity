# For Consideration

Deferred ideas that aren't scoped or committed to yet — revisit if they keep coming up in real use,
rather than building speculatively now. Items already tracked inline in BUILD_LOG.md's "Deliberately
deferred" notes (per-scene cascade gaps, etc.) aren't duplicated here; this file is for open design
questions, not known implementation gaps.

- **Annotations panel position (bottom vs. right-docked).** Currently always bottom-docked under
  the scene editor (Phase 4). A right-docked option would need to coexist with the Reference
  Panel, which already owns the right-hand slot with its own resize handle — stacking or tabbing
  the two would add real layout complexity. Hold off until the bottom panel actually feels cramped
  in day-to-day use.

- **Per-project vault passwords.** Current design is one password for the whole library
  (`VaultService`). Explicitly deferred when the vault/backup system was built — see BUILD_LOG.md.

- **Emailing/sharing exported review files directly from the app.** Currently the export/import
  and reviewer-session screens (Phase 4) just write files to a user-chosen path, plus a "Copy Path"
  snackbar action on the reviewer's comments export. Actual email sending would need its own
  SMTP/credential setup — a meaningfully bigger, separate feature with real security surface, not a
  bolt-on. A lighter middle step worth considering first: a "Reveal in Explorer" action next to the
  existing save dialogs.

- **Automatic on-foreground Drive sync.** PLAN.md's Google Drive Sync section calls for "manual Sync
  now + on-foreground background sync"; only the manual half is built. Would need a trigger wired to
  app-resume/project-open, probably debounced so it doesn't fire on every tab switch.

- **Side-by-side content preview on the Sync Conflicts screen.** Currently shows filename + Keep
  Local/Keep Drive/Keep Both actions only, no diff view of what actually changed. Version History's
  diff viewer (`scene_history_screen.dart`) does something similar and could potentially be reused
  for just the preview rendering, even with conflict *resolution* staying its own dedicated screen
  (a deliberate choice — see BUILD_LOG.md's Phase 5 section for why they're kept separate).

- **Multi-account / multi-Drive support.** One signed-in Google account for the whole app at a time,
  matching PLAN.md's v1 scope. Switching accounts means disconnect then reconnect.

- **Hypernym/hyponym (broader/narrower term) browsing in the thesaurus.** PLAN.md's original wording
  covered this; user scoped v1 down to synonyms + definitions only when the WordNet feature was
  built. `synsets.hypernym` data exists in the OEWN source but isn't loaded into `wordnet.sqlite` —
  would need a new table and a rebuild via `tool/build_wordnet_db.dart` if picked up later.

- **Android Keystore-backed encryption for the Drive OAuth refresh token.** Currently stored as a
  plain file under the app's private sandboxed storage on Android (Windows uses real DPAPI
  encryption via `CryptProtectData` — see `drive_token_store.dart`). Android's app-private storage
  already denies other apps access without root/backup extraction, so this is a defense-in-depth
  gap, not an open door — closing it needs a small custom platform channel into Android Keystore,
  not built this session.

- **A Settings section to view/manage words added to the spell-check dictionary.** Requested right
  after "Add to Dictionary" (spelling panel, Phase 4.5) shipped. Note this needs solving *underneath*
  the UI first, not just a new screen: `Hunspell_add` only adds to the in-memory run-time dictionary
  (`hunspell_ffi.dart`'s own doc comment already flags this) — nothing persists across an app
  restart today, so there's nothing yet for a Settings screen to actually list. Needs its own small
  persisted store (e.g. a `custom-words.txt` per language, replayed through `Hunspell_add` on load)
  before the management UI has anything real to manage.
