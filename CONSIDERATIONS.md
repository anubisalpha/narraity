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
  (Helvetica/WinAnsi) has no full Unicode support. A stopgap is now in place — `pdf_exporter.dart`'s
  `_pdfSafeText` normalizes smart quotes/dashes/ellipsis to their closest ASCII equivalent, so
  standard English typography no longer renders as missing-glyph boxes — but non-Latin scripts, or
  any character outside that small normalization list, still would. Embedding a real font file
  (e.g. via `google_fonts` or a bundled TTF) is the thorough fix, and a bigger call (which font,
  licensing, app size) than the normalization workaround.

- **`export-profile.json` reusable per-project export presets.** PLAN.md sketches a data model for
  saved export configurations (e.g. a named "kdp-print-6x9" preset); nothing reads or writes this
  file yet — every export today is a one-off "pick a format, pick a location" run.

- **Clicking a container node (Book/Chapter/Act) opens only its own — often empty — prose, not a
  combined view of its children.** This is existing, deliberate behavior for every project (every
  node can hold its own text independently of its children; the combined view exists separately as
  each node's "⋮" menu → "View everything in this section"), not something the manuscript importer
  introduced. It's landing harder for imported content though: Dabble's Book/Chapter levels never
  carry their own prose at all (only Scenes do), so clicking one always opens a blank editor, which
  reads as "nothing happened" until you know the combined view is a separate menu action. User
  tried the workaround, confirmed it works, but is unsure whether the current split (bare click vs.
  menu action) is the right default long-term, or whether it should be a configurable option.
  Revisit if this keeps causing confusion rather than changing it speculatively now.

- **The "chapter boundary" heuristic for PDF/DOCX page breaks and EPUB file grouping is a fixed
  keyword list** (`chapter`/`act`/`book`/`part`, case-insensitive — see
  `ManuscriptOutlineBuilder._chapterLikeLabels`), not a per-node or per-project setting. Covers
  every shape `manuscript_seeds.dart` offers, but a writer using an unlisted freeform `typeLabel`
  (e.g. "Volume") at a nested depth wouldn't get a page break there. No real case has surfaced this
  yet — revisit if a genuinely different label naming scheme shows up in practice, rather than
  building a configurable list speculatively now.

- **A series' library-card cover is picked automatically** (its most-recently-modified member
  project with a cover set — see `_SeriesStackCard._coverSourceProject` in `library_screen.dart`),
  not a cover belonging to the series itself. Fine while a series is small, but means the card's
  cover can change unexpectedly as books get edited. A dedicated series-level cover (independent of
  any member project's) would be the more correct model if this proves confusing in practice.
