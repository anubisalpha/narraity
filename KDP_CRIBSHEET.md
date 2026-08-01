# KDP Formatting Cribsheet

Consolidated rules pulled from Amazon KDP's own help docs, organized by what Narraity's export
pipeline needs to do about each one. This is the working reference for Phase 6.3 (KDP export) —
PLAN.md's Export feature section has the narrative version; this file is the flat checklist to
build/verify against and to re-diff when `tool/kdp_watch/check_kdp_pages.ps1` flags a source page
as changed.

**Scope reminder:** interior/manuscript export only. No cover formatting, wraparound/spine-width
PDF, or jacket mechanics — covers are handled entirely outside this feature (see PLAN.md).

**Status legend:** ✅ built · ⚠️ partially built / needs verification · ⬜ not built

Last refreshed: 2026-08-01, against the snapshots in `tool/kdp_watch/*.txt`. If `kdp-watch` files
a GitHub issue for a page, that page's row(s) below are the ones to re-check.

## Handling forward-dated rule changes

KDP occasionally announces a rule change with a stated future effective date (the MOBI→EPUB
transition worked this way) rather than just silently updating a page. When that happens, both
the old and new rule apply legitimately depending on which side of that date a user is submitting
on — so the export logic shouldn't just switch to "current" the moment we notice the page changed;
it should auto-select based on **today's date vs. the announced effective date**, and only fully
retire the old ruleset once that date passes.

Practical shape: when a rule row below is superseded by a dated announcement, add an
`Effective <date>` note directly on that row (old rule) and its replacement (new rule) rather than
just overwriting it. Export logic picks whichever ruleset is valid for the current date — no user
picker needed in the common case. Most `kdp-watch` diffs won't carry a stated effective date at
all (KDP usually just updates silently, effective immediately) — this only applies when KDP
explicitly announces one.

---

## Paperback

Source: [Format Your Paperback](https://kdp.amazon.com/en_US/help/topic/G201834190) · [Trim, Bleed, Margins](https://kdp.amazon.com/en_US/help/topic/GVBQ3CMEQW3W2VL6) · [Front/Body/Back Matter](https://kdp.amazon.com/en_US/help/topic/GDDYZG2C7RVF5N9J)
(watched as `paperback`, `trim-bleed-margins`, `front-body-back-matter`)

| Rule | Detail | Status |
|---|---|---|
| Trim size | Dropdown preset, not free entry — all 16 of KDP's published paperback sizes: 5"×8", 5.06"×7.81", 5.25"×8", 5.5"×8.5", 6"×9" (standard); 6.14"×9.21", 6.69"×9.61", 7"×10", 7.44"×9.69", 7.5"×9.25", 8"×10", 8.25"×6", 8.25"×8.25", 8.5"×8.5", 8.5"×11", 8.27"×11.69" (large) | ✅ Built 2026-08-01, corrected 2026-08-01 — `KdpTrimSize` enum, `kdp_paperback_exporter.dart`. Originally shipped with only 10 of the 16 sizes (missing the 6 listed above); fixed same day against KDP's full trim-size table |
| Page count range | Varies by **both** trim size and ink/paper type, not one flat number — see the full matrix below | ✅ Fixed 2026-08-01 — was previously a single hardcoded 24–828 regardless of trim size or ink type. `KdpInkPaperType` enum (5 values) + `KdpTrimSize.pageCountRange(inkPaperType)` extension now resolve the real range; `ExportScreen` gained an ink/paper dropdown (paperback only) to collect the input. `buildBytes`/`exportToFile` require `inkPaperType` unless `minPageCount`/`maxPageCount` are explicitly overridden (as `KdpHardcoverExporter` does for its own fixed 75–550 range) |
| Bleed | Interior: +0.125" (3.2mm) on the outer width edge only (spine side never bleeds) and +0.125" on both top and bottom (+0.25" total height); covers always need bleed, interior only if content runs to edge. Formula confirmed against KDP's own example (6"×9" trim -> 6.125"×9.25" with bleed) | ✅ Fixed 2026-08-01 — was previously doubling bleed on width too (6.25"×9.25", wrong); `pageFormatFor` now adds bleed once to width, twice to height |
| Margin/gutter scaling | Inside margin grows with page count (0.375"→0.875" across 5 bands); see table in PLAN.md's Paperback section | ✅ Built — `KdpPaperbackExporter.gutterInches(pageCount)`, exact KDP bands |
| Margin calc timing | Can't be computed once — page count depends on layout, layout depends on margin. Needs an iterate-until-stable layout pass | ✅ Built — two-pass build: guess the smallest band, get the real page count, rebuild once if that count lands in a different band. Caught a real bug along the way: `pw.Widget` instances can't be reused across two separate `pw.Document` builds (internal layout state), so each pass rebuilds its widget tree from scratch |
| Double-sided / mirrored margins | Standard for novels | ⚠️ **Confirmed structurally out of reach without a much bigger rewrite (verified 2026-08-01 against the `pdf` package's own source)**: `MultiPage`'s page format/margin are fixed at construction — there's no per-page-callback mechanism at all, only per-`MultiPage`. True mirroring would mean abandoning automatic flow-layout pagination entirely and hand-rolling page-by-page layout. Symmetric margins (same value every edge/page) remain the v1 approach; left/right both use the larger, binding-critical gutter value so the KDP minimum holds regardless of which edge is the real binding side whenever this gets revisited |
| Running headers | Left = author name, right = book title, alternating; off on chapter-title pages | ✅ Built 2026-08-01 — alternates by page parity (odd=title/recto, even=author/verso), suppressed on each chapter's own first page via per-chapter `MultiPage`s sharing one continuous whole-book page-index for numbering/parity, plus a separate chapter-relative index just for suppression. See `kdp_paperback_exporter.dart`'s class doc for two real bugs this caught (a shared instance field contaminating across sections; a call-counting suppression flag broken by the `pdf` package invoking header builders more than once per page) |
| Page numbering | Arabic numerals; front matter conventionally unnumbered/roman, body starts at 1 | ✅ Built 2026-08-01 — front matter gets lowercase roman numerals, body+back matter get Arabic restarting at 1, via three independently-numbered `pw.MultiPage`s (title/front matter/body) sharing one `Document`. Verified against actual rendered PDF text (not just page-count proxies), using an uncompressed-PDF test mode built specifically for this |
| Front matter order | half-title → title → copyright → reviews (opt) → dedication → ToC → preface (opt) → acknowledgments (opt) → prologue (opt) → introduction (opt) | ⚠️ Partially built 2026-08-01 — **copyright page**: ✅ auto-generated always, prepended as front matter's own first page (roman "i"), ahead of any of the project's own `SpecialSection`s. Uses `project.title`/`author` + current export year (no dedicated publication-year field exists) for standard boilerplate text. **Half-title page**: ⬜ still not built — no content type for it, and it needs real recto/verso enforcement (see below) to land correctly |
| Half-title/title placement | Always right-facing, no page number or header | ⬜ Not built — title page itself already has no page number/header (its own unnumbered `MultiPage`), but neither it nor a (still nonexistent) half-title page is forced onto a right-facing physical page; that needs blank-page-insertion logic this export doesn't have |
| Copyright page placement | First left-facing page after title | ⚠️ Partially built — copyright page exists and is placed immediately after title, but its facing side (left/right) isn't verified or enforced — same missing blank-page-insertion logic as half-title above |
| ToC accuracy | Must match body chapter names exactly | ✅ (Automatic ToC already guarantees this in-app) |
| First chapter | Starts right-facing | ⬜ Not built — depends on page numbering/facing-page tracking, deferred with running headers |
| Subsequent chapters | Start on next available page | ✅ (chapter-boundary page breaks already shared with general PDF export via `ManuscriptOutlineBuilder`) |
| Chapter-title pages | No header | N/A until running headers exist |
| Paragraph indent rule | Chapter's first paragraph: no first-line indent; subsequent paragraphs: indented | ⬜ Not yet ported from the EPUB/DOCX exporters — this specific exporter reuses `PdfWidgetBuilder`, which doesn't currently implement the first-paragraph-no-indent rule (general `PdfExporter` doesn't either) |
| Body text alignment | Fully justified | ⬜ Not verified — `pw.RichText`'s default alignment not explicitly checked/set |
| Back matter | Right-facing: bibliography/references, author bio, index (index = flush-and-hang, not v1 target) | ⬜ Not built (facing-page tracking dependency, same as front matter) |
| Output | Print-ready PDF, embedded fonts, correct trim+bleed box in the PDF itself | ⚠️ Trim+bleed box: ✅ done. Embedded fonts: still the same ASCII-normalization stopgap as general PDF export (`PdfWidgetBuilder.pdfSafeText`, shared with `PdfExporter`) — a real embedded Unicode font remains unbuilt, tracked in CONSIDERATIONS.md |
| Font embedding | Real embedded Unicode font needed — current PDF path only ASCII-normalizes (see CONSIDERATIONS.md) | ⚠️ (stopgap only) |

### Paperback page-count range by trim size + ink/paper type (confirmed 2026-08-01)

| Trim size | B&W/white | B&W/cream | Groundwood | Standard color | Premium color |
|---|---|---|---|---|---|
| 5"×8" – 6"×9" (5 standard sizes) | 24–828 | 24–776 | 24–812 | 72–600 | 24–828 |
| 6.14"×9.21" – 8"×10" (6 large sizes) | 24–828 | 24–776 | 24–812 | 72–600 | 24–828 |
| 8.25"×6", 8.25"×8.25" | 24–800 | 24–750 | 24–784 | 72–600 | 24–800 |
| 8.5"×8.5", 8.5"×11" | 24–590 | 24–550 | 24–578 | 72–600 | 24–590 |
| 8.27"×11.69" | 24–780 | 24–730 | 24–764 | **not available** | 24–590 |

## Hardcover

Source: [Format Your Hardcover](https://kdp.amazon.com/en_US/help/topic/GKYZRXFBZH2LDXAK) (watched as `hardcover`)

| Rule | Detail | Status |
|---|---|---|
| Cover mechanics | Case laminate — no dust jacket, art printed directly on case | N/A (covers out of scope) |
| Trim sizes | Distinct, smaller list: 5.5"×8.5", 6"×9", 6.14"×9.21", 7"×10", 8.25"×11" | ✅ Built 2026-08-01 — `KdpHardcoverTrimSize` enum, `kdp_hardcover_exporter.dart` |
| Page count range | 75–550 pages — narrower than paperback; needs its own validation message | ✅ Built — `KdpHardcoverExporter` defaults to 75/550 (paperback's `KdpPaperbackExporter` still defaults to 24/828), throws `KdpPrintExportException` naming the actual count if outside range |
| Bleed/margin rules | KDP's hardcover page is a hub pointing at the *same* trim/margin and front-body-back-matter sub-topics as paperback — no separate table found. Working assumption: paperback's rules apply, using hardcover's own trim/page-count bands. **Not 100% confirmed** | ⚠️ Built on the working assumption — `KdpHardcoverExporter` reuses `KdpPaperbackExporter`'s exact margin/bleed/numbering/header/copyright engine wholesale (a thin wrapper, not a reimplementation), so if this assumption is ever contradicted, only one place needs fixing. Re-checked 2026-08-01 against three separate KDP pages — "Set Trim Size, Bleed, and Margins" (`GVBQ3CMEQW3W2VL6`), "Format Your Hardcover" (`GKYZRXFBZH2LDXAK`), and "Paperback and Hardcover Manuscript Templates" (`G201834230`) — all three point at the same paperback-only table with zero hardcover-specific numbers. This appears to be a genuine gap in KDP's own docs, not a page we haven't found yet; treat further searching as low-yield unless KDP publishes something new |
| JP marketplace | Hardcover unsupported in JP — submission-side constraint, not an export-logic concern | N/A |

## eBook

Source: [Format Your eBook](https://kdp.amazon.com/en_US/help/topic/G201723130) (watched as `ebook`)

| Rule | Detail | Status |
|---|---|---|
| Format | EPUB (MOBI deprecated, Amazon converts from EPUB) | ✅ (general EPUB export already built) |
| Reflowable text | No trim/bleed/page-count constraints | N/A |
| Front matter in EPUB | Title page, copyright template, dedication, in correct order | ⚠️ (general EPUB export exists; KDP-specific front-matter ordering not verified) |

## Kindle Publishing Guidelines — Reflowable Text

Source: [Text Guidelines](https://kdp.amazon.com/help?topicId=GH4DRT75GWWAGBTU) (watched as `reflowable-text`)

| Rule | Detail | Status |
|---|---|---|
| Heading alignment | CSS `text-align` explicit on all headings | ⬜ verify against `styles.css` |
| Body text defaults | Default 1em font-size/line-height, not forced bold/italic throughout, no forced font-family | ⬜ verify |
| Font color | If used, grays only in #666–#999 range (luminance 102–153) | ⬜ verify |
| Body background | Never black or white | ⬜ verify |
| Margins/padding | Left/right = 0 for body text; % units if needed elsewhere; **no fixed px/pt anywhere** | ✅ verified 2026-08-01 — `epub_exporter.dart`'s `_stylesCss` uses only `%`/`em`/unitless values throughout, no px/pt found |
| Paragraph spacing | `text-indent` (max 4em) or line spacing, in em/%, not double-spaced | ⬜ verify |
| Drop caps | %/relative units only; specific CSS pattern documented in KDP docs if picked up | ⬜ (not planned for v1) |
| Page breaks | `page-break-*`/`break-*` CSS supported; insert after chapters/sections | ⚠️ (general export already does chapter-boundary page breaks for PDF/DOCX; EPUB/CSS-break equivalent not confirmed) |
| Embedded fonts | OTF/TTF only, no Type 1; licensing is publisher's responsibility | ⬜ (not yet offered for EPUB) |
| Font customization | Set primary font at `<body>` level, not per-paragraph — conflicting overrides get font files stripped by Amazon | ⬜ verify |
| ToC page numbers | Remove page numbers from ToC entries; keep as hyperlinks by section name | ✅ (Automatic ToC is link-based already, no page numbers by design) |
| Footnotes | Preferred: HTML5 `<aside epub:type="footnote">` + bidirectional links | ✅ Built 2026-08-01 — footnote annotations are numbered in document reading order, rendered as `<sup><a epub:type="noteref">`, with the matching `<aside epub:type="footnote">` placed at the end of the chapter file the reference appears in. PDF/DOCX exporters still don't touch footnotes at all — tracked separately in CONSIDERATIONS.md as a cross-format gap, out of scope for this eBook-only pass |
| MathML | Supported subset of tags for Enhanced Typesetting | N/A (not a Narraity feature) |

## Kindle Publishing Guidelines — Reflowable Images

Source: [Image Guidelines](https://kdp.amazon.com/help?topicId=G75V4YX5X8GRGXWV) (watched as `reflowable-images`)

| Rule | Detail | Status |
|---|---|---|
| Formats | JPEG, PNG, single-frame GIF only — no TIFF, no multi-frame GIF, no transparency (auto-converted to white bg) | ⬜ — **no image embedding in any export format yet at all** (CONSIDERATIONS.md gap) |
| Color profile | sRGB only; CMYK auto-converted | ⬜ |
| Sizing | Pictorial images ≥60% screen width on small devices; text-containing images (diagrams/graphs) ≥80% | ⬜ |
| Placement | Block (`display:block`, 100% width), float (20% width + float), inline (height in em) | ⬜ |
| Alt text | Required on all images; decorative images use `alt=""` or `role="presentation"` | ⬜ |
| Text-as-image | Avoid — use real HTML text for captions/titles/table content | ⬜ |

## Kindle Publishing Guidelines — Reflowable Tables

Source: [Table Guidelines](https://kdp.amazon.com/help?topicId=GZ8BAXASXKB5JVML) (watched as `reflowable-tables`)

| Rule | Detail | Status |
|---|---|---|
| Supported markup | Standard `<table>`/`<thead>`/`<tbody>`/`<tfoot>`, `colspan`/`rowspan`, nested tables (use sparingly) | 🚫 Blocked, confirmed 2026-08-01 — the editor is a plain markdown-lite `TextField` (no `flutter_quill` dependency, contrary to an earlier assumption in this doc), with no table-authoring UI at all. Nothing to export until table authoring exists as its own editor feature |
| Hard limit | >1,800 cells or >20,000 characters unsupported | ⬜ |
| Recommended size | <100 rows × 10 columns | ⬜ |
| Styling | No negative margins, no empty padding columns, no floats inside tables, `caption-side:bottom` unsupported | ⬜ |

## Kindle Publishing Guidelines — Navigation

Source: [Navigation Guidelines](https://kdp.amazon.com/help?topicId=GY3AD8C6C6GAG42N) (watched as `navigation-guidelines`)

| Rule | Detail | Status |
|---|---|---|
| HTML ToC placement | Near the beginning of the book, not the end (affects sample downloads + Last Page Read) | ✅ (Automatic ToC is front-matter positioned already) |
| HTML ToC structure | Clickable links, no `<table>` tags for layout, no page numbers | ✅ |
| **Logical ToC nesting cap** | **Kindle supports only 2 levels of nesting in the nav doc/NCX** | ✅ Built 2026-08-01 — `EpubExporter._navList` now collapses any depth beyond the shallowest boundary group into a second level, never nesting further; tested against a Book>Act>Chapter tree (3 nominal depths → 2 actual nav levels) |
| nav element (EPUB3) | `properties="nav"` in manifest | ✅ verified — `_contentOpf` already emits `properties="nav"` on the nav item |
| NCX (EPUB2) | `toc="toc"` in spine if targeting EPUB2 compatibility | N/A if EPUB3-only |
| Guide items / landmarks | Optional but recommended — cover/ToC/beginning references; without them, some Kindle menu items show grayed out | ⬜ |

## Kindle Publishing Guidelines — QA Standards

Source: [QA Standards](https://kdp.amazon.com/help?topicId=GGRXLC5USU4H67YM) (watched as `qa-standards`)

| Rule | Detail | Status |
|---|---|---|
| **File size limit** | Each HTML file inside the EPUB must be **<30MB** | ✅ Built 2026-08-01 — `EpubExporter` throws `EpubExportException` at export time if any section file would exceed the limit (configurable, defaults to the real 30MB) |
| **File count limit** | EPUB must contain **fewer than 300 HTML files** | ✅ Built 2026-08-01 — same exception, checked against total section count + nav.xhtml (configurable, defaults to 300) |
| Cover present, no duplicate | Book must have a cover; no duplicate cover on first page-flip | N/A (covers out of scope for this feature) |
| ToC functional | All entries clickable, correct targets, no page numbers | ✅ (per above) |
| Text/typography checks | No forced bold/italic, alignment correct, typeface changes apply | ⬜ verify |
| Full flip-through | Images legible/scaled, tables render correctly, no CD/DVD references, all 4 background modes (white/black/mint/sepia) legible | ⬜ (manual pre-release check, not export-time logic) |
| Accessibility compliance | Headings nested correctly, links described, 4.5:1 contrast, tables structured, image alt text | ⬜ — see Accessibility section below |

## Kindle Publishing Guidelines — Accessibility

Source: [Accessibility Guidelines](https://kdp.amazon.com/help?topicId=GF9Z3HLUMTRJ6QPL) (watched as `accessibility-guidelines`)

| Rule | Detail | Status |
|---|---|---|
| Language tagging | Define primary language; tag language changes in content | ✅ Built 2026-08-01 — every XHTML document (`nav.xhtml` and every section file) declares `xml:lang="en"`/`lang="en"`, matching `content.opf`'s existing `dc:language`. Per-run language changes within content (e.g. a foreign phrase) aren't tracked — no real case has surfaced needing it |
| Heading hierarchy | Proper nesting for chapters/sections/subsections | ⚠️ (headings exist in the editor; EPUB nav-doc hierarchy correctness not verified) |
| Lists | Use real ordered/unordered list markup | N/A unless/until list support is confirmed in the editor |
| Table headers | Row/column headers when tables exist; never render tables as images | 🚫 Blocked — no table support exists to attach headers to (see Reflowable Tables above) |
| Image alt text | Required for meaningful images; `alt=""` for decorative | 🚫 Blocked — no image embedding exists in any export format yet (see CONSIDERATIONS.md) |
| Link descriptions | Self-describing link text, avoid repeated identical link text on a page | N/A (no in-book hyperlinks feature currently) |
| **Color contrast** | **WCAG minimum 4.5:1 text/background contrast** | ✅ N/A by default, verified 2026-08-01 — `styles.css` sets no explicit text or background color anywhere, so every reader renders it as their own default (near-black text on their chosen background), which is inherently compliant. Only becomes a live concern if/when a custom font-color picker becomes export-facing — nothing like that exists today |
| MathML | For equations, if ever needed | N/A |

---

## Open research still needed before build

- Hardcover-specific bleed/margin tables — currently assumed identical to paperback, not
  independently confirmed (KDP's hardcover page is a hub, not a spec page)
- Spine width formula — moot now that covers are out of scope, but flagging in case scope ever
  changes
- Whether `flutter_quill` (the editor) supports authoring tables at all — blocks any table-export
  work regardless of what KDP allows

## Supported/ignored tags — Kindle Format 8 (fetched 2026-08-01, `GB5GDY7WAJDN9GFK`)

Source: "HTML and CSS Tags Supported in Kindle Format 8" (/en_US/help/topic/GB5GDY7WAJDN9GFK).

- **Supported:** `a`, `address`, `aside`, `b`, `bdi`, `bdo`, `blockquote`, `body`, `caption`,
  `center`, `cite`, `code`, `col`, `dd`, `del`, `div`, `dl`, `em`, `figure`, `h1`–`h6`, `hr`, `i`,
  `image`, `img`, `li`, `listing`, `mark`, `ol`, `p`, `plaintext`, `pre`, `rb`, `rt`, `ruby`, `s`,
  `samp`, `strike`, `strong`, `table`, `tbody`, `td`, `tfoot`, `th`, `thead`, `tr`, `tt`, `ul`,
  `var`, `xmp`, `-webkit-background-size`
- **Ignored regardless of attributes/units/values:** `area`, `big`, `ins`, `kbd`, `map`, `mbp:nu`,
  `reference`, `small`, `time`

**Gap found and fixed 2026-08-01:** `sup` (and `sub`) appear in **neither** list. The footnote
reference marker previously used `<sup><a epub:type="noteref">...</a></sup>` (built as part of the
footnote-to-`<aside>` round-trip, Phase 4). ✅ Fixed — `epub_exporter.dart` now emits a plain
`<a class="footnote-ref" epub:type="noteref">` with `vertical-align: super; font-size: 0.7em;` in
`styles.css` instead of `<sup>`, giving the same visual raised/small reference number via a tag
that's on the supported list. (`<small>` was considered and rejected — it's explicitly on the
*ignored* list above, so it wouldn't have been a safe substitute either.)
