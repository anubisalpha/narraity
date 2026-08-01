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

- **KDP Kindle Publishing Guidelines gaps against the EPUB exporter** (found reviewing KDP's
  guidelines hub, 2026-08-01, ahead of Phase 6.3 — see PLAN.md's eBook section and
  `KDP_CRIBSHEET.md` for full detail). The eBook path is now built as far as it can be without
  other unbuilt features: 2-level ToC nesting cap, 30MB/300-file hard limits, footnote-to-`<aside>`
  round-trip, and language tagging are all done; `styles.css`'s units and color-contrast were
  audited and found already compliant. Still genuinely blocked:
  - **PDF/DOCX footnote support** — the EPUB exporter now handles footnotes (numbered in reading
    order, `<sup><a epub:type="noteref">` + `<aside epub:type="footnote">` at the enclosing
    chapter's end), but PDF and DOCX still don't touch `annotation_service.dart`/footnote
    annotations at all. The character-offset-anchor-to-rendered-output mapping now exists as a
    proven pattern (private-use-area marker inserted pre-parse, substituted post-render) — porting
    it to PDF/DOCX is the remaining work, not a new design problem.
  - **Table support** — confirmed 2026-08-01: the editor is a plain markdown-lite `TextField`, not
    `flutter_quill` (an earlier, incorrect assumption in this doc) — there's no table-authoring UI
    at all, so there's nothing for any exporter to support yet. Blocked on that editor feature
    existing first, not an export-side gap.
  - **Image alt text** — blocked on image embedding existing in exports at all (a separate,
    already-tracked gap below).

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
  - **First-paragraph-no-indent and justified-body-text** rules (already correct in the EPUB
    exporter) haven't been ported to `PdfWidgetBuilder`, which both `PdfExporter` and
    `KdpPaperbackExporter` share — worth doing together rather than duplicating per-exporter.

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

- **Release notes in the app.** No in-app "what's new" surface exists — the update checker
  (`update_check_service.dart`) links out to GitHub's release page rather than showing changelog
  content itself. Worth revisiting once there's a real backlog of releases to show; v1.0.1 is
  still the only one.

- **A News page, fed from a page in the repo, updatable when internet access is available.**
  Similar mechanism to the update checker's GitHub API polling — could fetch a `NEWS.md` (or
  similar) from the repo's raw content URL, cache locally, and show in-app, refreshing whenever
  online. Not scoped: how often to check, whether it needs its own opt-out (some users may not
  want any outbound network calls beyond the existing opt-in Drive sync and the update checker),
  and how it'd differ from just directing users to the GitHub releases page the update checker
  already links to.

- **A Feedback page, with voice-to-text input.** The voice dictation infrastructure from Phase 1.3
  (Vosk on Windows, native `SpeechRecognizer` on Android) already exists and could be reused for a
  feedback text field. The open question is delivery, not capture: there's no SMTP/email-sending
  feature (see the existing "Emailing/sharing exported review files" item above — same gap
  applies), and having a shipped end-user app silently file GitHub issues on the user's behalf
  (the way `kdp-watch` does for the dev-only page-monitoring case) isn't appropriate without the
  user's own GitHub auth. Needs a decision on the actual transport (mailto: link, a lightweight
  hosted endpoint, or requiring the user to have their own GitHub account) before this is buildable.

- **KDP hardcover interior margin/bleed rules have no independently-confirmed source.** Not a
  "haven't looked yet" gap — re-checked 2026-08-01 across three separate KDP help pages (trim/
  bleed/margins, "Format Your Hardcover", and the paperback/hardcover manuscript templates page),
  all three point at the same paperback-only table with no hardcover-specific numbers. The current
  build's working assumption (hardcover interior uses paperback's margin/bleed rules, banded by
  hardcover's own trim sizes/page counts) is the best answer available from KDP's own docs. See
  `KDP_CRIBSHEET.md`'s Hardcover section and `PLAN.md`'s open questions for full detail; only worth
  revisiting if KDP publishes something new.
