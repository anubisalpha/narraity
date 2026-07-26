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

- **A visible "syncing now" indicator outside the Settings screen.** Automatic sync (immediate
  per-file, daily, frequent) runs silently in the background; the Sync Log (Settings → Google Drive
  Sync → Sync Log) is the only place to confirm it actually happened. A persistent status icon
  somewhere in the app shell (synced/syncing/error) was discussed but not built.

- **The "more frequent sync" interval is a fixed preset list** (off/5/15/30/60 min), not a free-form
  number field — deliberately, to keep the Settings UI a simple dropdown rather than validating
  arbitrary input.

- **No explicit coalescing between a periodic tick and an immediate per-file sync landing on the
  same project at the same moment.** Harmless today (worst case: two sequential syncs, the second a
  no-op), but not actively deduplicated if it turns out to matter in practice.

- **Side-by-side content preview on the Sync Conflicts screen.** Currently shows filename + Keep
  Local/Keep Drive/Keep Both actions only, no diff view of what actually changed. Version History's
  diff viewer (`scene_history_screen.dart`) does something similar and could potentially be reused
  for just the preview rendering, even with conflict *resolution* staying its own dedicated screen
  (a deliberate choice — see BUILD_LOG.md's Phase 5 section for why they're kept separate).

- **Multi-account / multi-Drive support.** One signed-in Google account for the whole app at a time,
  matching PLAN.md's v1 scope. Switching accounts means disconnect then reconnect.

- **A Settings toggle to actually turn spell check off.** `spellCheckEnabledProvider` is now
  correctly persisted (fixed alongside the App Settings sync work — it used to silently reset to
  "on" every launch), but nothing in the UI sets it yet; there's no toggle anywhere to turn it off
  in the first place. Small, standalone follow-up.

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

- **KDP-ready print/ebook export (Phase 6.3).** General export (PDF/DOCX/EPUB/plain text) is built;
  the print-specific path — trim size presets, automatic margin/gutter calculation scaled to page
  count, running headers, single- vs double-sided, and a separately-exported wraparound print cover
  with auto-calculated spine width — is a distinct enough sub-feature to need its own dedicated UI
  and design pass, not built alongside general export.

- **Image embedding in exports.** None of the four export formats (PDF/DOCX/EPUB/plain text) embed
  cover or in-book images yet, even though Character/World profiles already support images. PLAN.md's
  PDF/DOCX spec calls for "full fidelity: images, formatting, fonts, page layout" — this is a real
  gap against that, not a deliberate simplification.

- **A real embedded Unicode font for PDF export.** The `pdf` package's default base font
  (Helvetica/WinAnsi) has no full Unicode support — fine for English prose and standard typographic
  punctuation, but non-Latin scripts would render incorrectly. Embedding a real font file (e.g. via
  `google_fonts` or a bundled TTF) would close this.

- **`export-profile.json` reusable per-project export presets.** PLAN.md sketches a data model for
  saved export configurations (e.g. a named "kdp-print-6x9" preset); nothing reads or writes this
  file yet — every export today is a one-off "pick a format, pick a location" run.
