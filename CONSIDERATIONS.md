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

- ~~**Per-project vault passwords.**~~ — ✅ Engine built (opt-in override; UI still pending). A
  project can now opt into its *own* vault password, distinct from the library-wide one, while
  unopted projects keep using the library key unchanged — no forced migration. `VaultService`
  itself was already password-per-call; the work was in the provider layer
  (`projectSigningKeyManagerProvider`/`effectiveSigningKeyManagerProvider` route each project's
  scene-history signing to the right key, backed by `_Vault/<folder>/salt`+`verifier`) and
  `VaultActions` (`setProjectPassword` re-signs history onto the new key with the same
  verify-then-write + rollback ordering as `changePassword`; `unlockProject`/`lockProject`;
  `removeProjectPassword` re-signs back to the library key and requires the library vault). The
  library-wide `changePassword` now skips opted-in projects (their history isn't signed with the
  library key). Covered by `vault_per_project_password_test.dart` (opt-in from library-key and from
  unsigned history, per-project lock/unlock across a restart, backup encrypted with the project
  password, library-password rotation leaving an opted-in project untouched, opt-out round-trip).
  **Still to do:** the Settings/vault UI to drive these actions (set/change/remove a per-project
  password, per-project unlock prompt) — the engine is done and tested, but nothing surfaces it in
  the app yet. One accepted residual risk, identical to the existing `changePassword`: a crash
  in the narrow window between re-signing history and writing the verifier could leave a project's
  history signed with a key whose verifier isn't yet on disk.

- **Emailing/sharing exported review files directly from the app.** Currently the export/import
  and reviewer-session screens (Phase 4) just write files to a user-chosen path, plus a "Copy Path"
  snackbar action on the reviewer's comments export. Actual email sending would need its own
  SMTP/credential setup — a meaningfully bigger, separate feature with real security surface, not a
  bolt-on. A lighter middle step worth considering first: a "Reveal in Explorer" action next to the
  existing save dialogs.

- ~~**A visible "syncing now" indicator outside the Settings screen.**~~ — ✅ Built (the doc was
  stale here). `status_bar.dart`'s `_DriveStatusIndicator` sits in the app-shell bottom bar and
  shows connected (green `cloud_done`) / connecting (amber) / not-connected (grey `cloud_off`), and
  **pulses while a sync is actively running** (`driveSyncActiveProvider`); tapping it explains the
  state. The one genuine gap — a failed *background* sync left the icon reassuringly green, visible
  only in the Sync Log — is now closed too: `driveLastSyncErrorProvider` drives a red
  `sync_problem` state (set on any target's failure, cleared on the next clean run), outranking the
  plain "connected" look. Covered by `drive_auto_sync_provider_test.dart`.

- **The "more frequent sync" interval is a fixed preset list** (off/5/15/30/60 min), not a free-form
  number field — deliberately, to keep the Settings UI a simple dropdown rather than validating
  arbitrary input.

- **No explicit coalescing between a periodic tick and an immediate per-file sync landing on the
  same project at the same moment.** Harmless today (worst case: two sequential syncs, the second a
  no-op), but not actively deduplicated if it turns out to matter in practice.

- ~~**Side-by-side content preview on the Sync Conflicts screen.**~~ — ✅ Built: each conflict tile
  now has a "Show what changed" expander that lazily calls `DriveSyncService.conflictPreview`
  (reads the local file, downloads the Drive side) and renders an inline character diff via the new
  shared `InlineTextDiff` widget — extracted from Version History's diff pane, so both screens now
  share one renderer instead of duplicating the `diff_match_patch` markup. Binary targets (cover /
  in-book images, Archived/Deleted zips) show a "binary file — no text preview" notice instead of
  garbage, gated by a text-extension allowlist. Conflict *resolution* stays its own dedicated
  screen as before (deliberate — see BUILD_LOG.md's Phase 5 section). Covered by two
  `conflictPreview` tests.

- **Multi-account / multi-Drive support.** One signed-in Google account for the whole app at a time,
  matching PLAN.md's v1 scope. Switching accounts means disconnect then reconnect.

- **Hypernym/hyponym (broader/narrower term) browsing in the thesaurus.** PLAN.md's original wording
  covered this; user scoped v1 down to synonyms + definitions only when the WordNet feature was
  built. `synsets.hypernym` data exists in the OEWN source but isn't loaded into `wordnet.sqlite` —
  would need a new table and a rebuild via `tool/build_wordnet_db.dart` if picked up later.

- ~~**Android Keystore-backed encryption for the Drive OAuth refresh token.**~~ — ✅ Built (Dart
  side; native half needs an on-device verification pass before release, see below). A
  hardware-backed AES-256-GCM Keystore key (`SecretCipher.kt`, method channel
  `uk.aity.narraity/secret_cipher`) now encrypts the OAuth tokens at rest on Android, via a shared
  `KeystoreFileSecret` helper. Scope note: this covers **both** OAuth tokens — the Drive refresh
  token *and* the GitHub access token (`android_secret_cipher.dart` is shared by both stores). The
  third secret this doc used to imply was at risk, the vault/history signing key, was never
  actually stored on disk — `HistorySigningKeyManager` derives it from the password (Argon2id) and
  holds it in memory only, so there was nothing to encrypt there. If the Keystore is unavailable
  the helper falls back to the old plain-file behaviour, so it's strictly an improvement, never a
  sign-in regression; a legacy plaintext token is upgraded to encrypted the next time it's read.
  `KeystoreFileSecret`'s file/fallback/migration logic is covered by
  `android_secret_cipher_test.dart` (with a fake cipher); the actual Keystore crypto in the Kotlin
  can only be verified by an on-device/emulator Android build, which hasn't run yet — flagged in
  BUILD_LOG.md as the one unverified piece.

- **KDP-ready print/ebook export (Phase 6.3).** General export (PDF/DOCX/EPUB/plain text) is built;
  the print-specific path — trim size presets, automatic margin/gutter calculation scaled to page
  count, running headers, single- vs double-sided, and a separately-exported wraparound print cover
  with auto-calculated spine width — is a distinct enough sub-feature to need its own dedicated UI
  and design pass, not built alongside general export.

- **Image embedding in exports.** None of the four export formats (PDF/DOCX/EPUB/plain text) embed
  cover or in-book images yet, even though Character/World profiles already support images. PLAN.md's
  PDF/DOCX spec calls for "full fidelity: images, formatting, fonts, page layout" — this is a real
  gap against that, not a deliberate simplification.

- ~~A real embedded Unicode font for PDF export~~ — ✅ Fixed 2026-08-10 (v1.6.0): a real embedded
  font (Noto Sans, 4 static weights) is now loaded via `PdfFonts` and wired into every
  `pw.Document(theme: ...)` across `PdfExporter`/`KdpPaperbackExporter`/`KdpHardcoverExporter`. The
  old `pdfSafeText` ASCII-normalization pass still runs as a harmless secondary step, no longer the
  primary fix.

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

- **KDP Kindle Publishing Guidelines gaps against the EPUB exporter** (found reviewing KDP's
  guidelines hub, 2026-08-01, ahead of Phase 6.3 — see PLAN.md's eBook section and
  `KDP_CRIBSHEET.md` for full detail). The eBook path is now built as far as it can be without
  other unbuilt features: 2-level ToC nesting cap, 30MB/300-file hard limits, footnote-to-`<aside>`
  round-trip, and language tagging are all done; `styles.css`'s units and color-contrast were
  audited and found already compliant. Remaining gaps:
  - ~~**PDF/DOCX footnote support**~~ — ✅ Fixed (v1.6.0, 2026-08-10): the character-offset-anchor
    pattern (private-use-area marker inserted pre-parse via `FootnoteMarkers`, substituted
    post-render) was ported from EPUB to both. DOCX emits real Word footnotes
    (`<w:footnoteReference>` + a `word/footnotes.xml` part); PDF renders in-text superscript markers
    (`¹²³`) plus an end-of-chapter numbered body list (`PdfWidgetBuilder.footnoteListWidgets`) —
    true page-bottom footnotes stay impossible under the `pdf` package's fixed-margin /
    no-per-page-callback model, so the end-of-chapter list is the deliberate substitute. See
    `docx_exporter.dart` and `pdf_widget_builder.dart`.
  - **Table support** (still blocked) — confirmed 2026-08-01: the editor is a plain markdown-lite `TextField`, not
    `flutter_quill` (an earlier, incorrect assumption in this doc) — there's no table-authoring UI
    at all, so there's nothing for any exporter to support yet. Blocked on that editor feature
    existing first, not an export-side gap.
  - **Image alt text** (still blocked) — blocked on image embedding existing in exports at all (a
    separate, already-tracked gap below).

- **KDP paperback export gaps** (`kdp_paperback_exporter.dart`, built 2026-08-01 — see
  `KDP_CRIBSHEET.md`'s Paperback section for full detail). Trim size, bleed, page-count-banded
  gutter margins, roman/Arabic page numbering, alternating running headers (with correct
  chapter-opening-page suppression), and an auto-generated copyright page are all built. Still open:
  - **True mirrored (odd/even) margins — confirmed structurally out of reach without a much
    bigger rewrite** (verified 2026-08-01 by reading the `pdf` package's own source):
    `MultiPage`'s page format/margin are fixed at construction with no per-page-callback mechanism
    at all. True mirroring would mean abandoning automatic flow-layout pagination entirely and
    hand-rolling page-by-page layout — a different project, not a follow-up task. Symmetric
    margins (same value every edge/page, using the larger gutter value on both left and right so
    the KDP minimum holds regardless of which edge is the real binding side) remain the v1 and
    likely long-term approach unless full manual pagination is ever built for other reasons.
  - **Half-title page and true recto/verso (right/left-facing) enforcement.** The copyright page
    is built and placed right after title, but neither it nor a (still nonexistent) half-title page
    is forced onto the correct facing side — that needs blank-page-insertion logic (e.g. "if title
    would otherwise land on a left-facing page, insert one blank page first to push it to the
    right") that doesn't exist yet. A real half-title page also needs its own content type, since
    Narraity has no concept of one today.
  - ~~First-paragraph-no-indent and justified-body-text rules haven't been ported to
    `PdfWidgetBuilder`~~ — ✅ Fixed 2026-08-11: `PdfWidgetBuilder.ParagraphIndentState` tracks a
    fresh "first paragraph" flag per chapter-boundary group (reset the same place footnote groups
    already reset), non-first paragraphs get a literal leading-space first-line indent
    (`spansFor(..., indent: true)`), and paragraph `RichText` widgets set
    `textAlign: pw.TextAlign.justify`. Shared by both `PdfExporter` and `KdpPaperbackExporter`,
    covered by a new `test/export/pdf_widget_builder_test.dart`.

- **Dual-ruleset KDP export for forward-dated rule changes.** If KDP ever announces a rule change
  with a stated future effective date (precedent: the MOBI→EPUB transition), both the old and new
  rules are legitimately valid depending on submission date — a user mid-project when the cutover
  happens shouldn't be forced onto the new rules before they're actually required. Not building a
  general "pick any past ruleset" export option (KDP only evaluates uploads against current-at-
  submission rules, so exporting against stale rules by choice just risks rejection) — but *if* a
  dated transition is ever announced, the export logic could auto-select the correct ruleset by
  comparing today's date to the announced effective date, no manual picker needed. See
  `KDP_CRIBSHEET.md`'s "Handling forward-dated rule changes" section for how such a change would
  get recorded if one shows up. Nothing tracked today carries a future effective date, so there's
  nothing to build yet.

- **KDP hardcover interior margin/bleed rules have no independently-confirmed source.** Not a
  "haven't looked yet" gap — re-checked 2026-08-01 across three separate KDP help pages (trim/
  bleed/margins, "Format Your Hardcover", and the paperback/hardcover manuscript templates page),
  all three point at the same paperback-only table with no hardcover-specific numbers. The current
  build's working assumption (hardcover interior uses paperback's margin/bleed rules, banded by
  hardcover's own trim sizes/page counts) is the best answer available from KDP's own docs. See
  `KDP_CRIBSHEET.md`'s Hardcover section and `PLAN.md`'s open questions for full detail; only worth
  revisiting if KDP publishes something new.
