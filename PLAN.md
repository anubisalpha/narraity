# Narraity — Novel Writing App

**App name status:** DECIDED (2026-07-24) — **Narraity**. Formerly working title "Imaginaity"
(project folder and all naming below renamed accordingly). Candidates tested and
rejected for existing app-store/company collisions: InkAtlas, Fingo, Ingenium, Fingere, Quillium,
Xendex, Bindcast (existing B2B comms company, bindcast.com). Interweave — no direct app/software
collision found, but overlaps with Interweave Press (craft/hobby publisher) in a different
industry; unverified trademark status. Imaginis — cleanest real-word candidate so far (no
app-store collision, only a same-named unrelated health website and a small consultancy).
**Theolindry** and **Bindarity** — user-coined/invented words, both confirmed zero collisions
(app stores, companies, trademarks) in searches performed; distinctive but neither inherently
signals "writing" without a tagline. Castnbind — technically unclaimed but reads awkwardly as a
brand name (leads to Bindcast variant, which is taken). Plotbind — exact string unclaimed, but too
close to existing "Plot Bound" (plotbound.com, a KDP write/publish/market service — same audience
and purpose) and the well-known "Plottr" story-plotting app; risks confusion despite no exact
match. Musings — exact app already live on Google Play (note-capture app), also "Muse"/"Allume" is
a well-known adjacent idea-development app. Fictionary — hard collision, an established real
competitor (fictionary.co, book writing/editing software with paid tiers) in the exact same
product category. **Cropula** — clean, no real collision (only a song and an unrelated game
costume name); invented-feeling like Theolindry/Bindarity, carries no inherent "writing" meaning
without a tagline. Novast — rejected, exact match to Novast Pharmaceuticals/Novast Holdings (real
multinational pharma company, Eli Lilly partnership); different industry but direct corporate name
match, too risky. Infinaity — rejected, exact match to InfinAIty.net, a live AI content-generation
platform; also broader "Infinity/INFINITI" namespace very crowded. LastChapter/"Last Chapter" —
rejected, live Google Play app of that exact name (series progress tracker), plus multiple real
bookstores and other sites using the phrase. Wordcaster — rejected, live Steam game of that exact
name plus an established Pathfinder RPG spellcasting term. All recorded as possibles, none
decided. Naming direction shifted 2026-07-13: user wants short, punchy, invented words (Dabble-like
energy) rather than literal/-aity-style names — Theolindry/Bindarity/Imaginis/Cropula rejected as
"not personal/exciting enough," not for collisions. **Autheritus** — clean, no app/company/software
collision found; echoes "author" and Latin roots (auctoritas/authenticus); only minor risk is one
forum post using it as a misspelling of "arthritis," not a real conflict. Currently a strong
candidate under the new short/punchy/invented direction. NovelPlan/NovelPlanner — rejected on fit,
not collision; too generic/descriptive, sits in an extremely crowded "novel planning" category
(Story Planner, Plottr, Novelcrafter, Hiveword, Pluot, Fabula, Wavemaker all occupy this naming
space) and doesn't match the punchy/invented direction. Wordcaster — rejected, live Steam game +
established Pathfinder RPG term. **Literation** — clean for software/app purposes (no app, company,
or product collision found); real dictionary word (Merriam-Webster/OED, dates to 1783, "the
representation of sound/words by letters"), carries genuine etymological weight rather than being
purely invented. Only adjacent hit is Literations.org, a Boston children's-literacy nonprofit — not
a commercial/software conflict. Strong candidate. Fusionary — rejected, established software/tech
consulting firm since 1995 (fusionary.com, Grand Rapids MI + UK arm), real corporate presence
(Crunchbase, LinkedIn); direct industry overlap. Flipside — rejected, heavily oversaturated (6+
live apps exactly named Flipside: Google Play app, App Store "FlipSide Social," "Flixel Flipside,"
a VR platform on Meta Quest, a blockchain analytics platform, a word game, a gym-management SaaS).
Edictation — rejected, live Google Play app "EDictation - English Dictation" plus an open-source
GitHub dictation app of the same name; functional overlap with Imaginaity's own dictation feature
makes this collision worse than usual.
Etymation — rejected, exact match to an established educational brand (etymation.com, an animated
K-12 cartoon series about English spelling history, with an academic paper written about it).
Fictus — rejected, live app "Fictus: Collaborative Storytelling" (fictus.app, Google Play) in the
same storytelling category, plus a separate Brazilian digital-wallet app of the same name. (Latin
participle of fingere, same root family as the already-rejected "Fingo.")
Storyscape — rejected, 3+ live apps under this exact name (kids' reading app storyscapeapp.com,
FoxNext interactive story game, StoryScape AI).
**Loretica** — clean, no app/software/company collision (only personal social-media handles and an
old genealogical name); evokes "lore," nearby non-conflicting tools are Lorekit/Lore (RPG
worldbuilding software, not novel-writing, no exact match). Third clean candidate alongside
Literation and Autheritus. Scribity — no exact app/company collision, but "Scrib-" prefix is one
of the most crowded neighborhoods encountered (Scrivener, Scribit, Scribie, Scribe, Scribly,
Scribbr, Scribely, SCRIBZEE all live products); risks being misheard/confused with Scrivener
specifically. Technically available but not recommended.
TBC — rejected as a literal name candidate: 6+ live unrelated apps/companies already use bare
"TBC" (Trimble Business Center, TBC Software, TBC Now, TBC Business, TBC Global, TBC Luxury
Resale), and a 3-letter acronym is hard to own distinctly regardless. Also doubles as shorthand for
"to be confirmed" — app name is currently, literally, TBC: shortlist is **Literation**,
**Autheritus**, **Loretica**, decision deferred.

A self-contained, local-first novel writing app (Windows + Android) inspired by Dabble, built to
remove Dabble's pain points: subscription lock-in, cloud-only storage, no import, narrow export,
and disconnected worldbuilding notes. Syncs via the user's own Google Drive instead of a
proprietary backend.

## Why build this instead of using Dabble

- Own the data: plain, portable files instead of a proprietary cloud store
- No subscription — one-time build, sync via user's own free Google Drive quota
- Import isn't an issue (files are yours from day one); export isn't limited to .docx
- Three features Dabble lacks that we're building in from the start:
  - **Reference Panel** — contextual worldbuilding/character info alongside the editor, not a
    separate screen you navigate away to
  - **Adaptive goal engine** — deadline or word-count goals that auto-redistribute daily targets
    across a working calendar, not a static number you recalculate yourself
  - **Version history** — automatic background snapshots plus named checkpoints, per scene, with
    diff view and restore — Dabble has no version control at all
  - **Global Ideas** — a capture space outside any single novel project, for ideas that don't have
    a home yet, with a promotion path into a project once they do
  - **AI/External Review Round-Trip** — export with stable anchors, import structured comments
    back into the exact right spot
  - **Timeline page** — in-story chronology (distinct from manuscript order), multiple parallel
    tracks, linked to scenes/characters/world entries
  - **Family tree / relationship diagram** — visual character relationship mapping, not just
    editable text fields
  - **Multi-novel series support** — group books into a series with shared characters/worldbuilding
    while keeping manuscripts, plot grids, and todos per-book
  - **Voice-to-text dictation** — offline-capable on both platforms, integrated into the normal
    editor flow rather than a separate transcription tool

## Tech stack

- **Flutter** — single codebase, all five platforms Flutter natively supports: Windows, Android,
  macOS, iOS, Linux. **v1 build/ship target is Windows + Android only**; macOS/iOS/Linux are not
  in the v1 build matrix but the architecture below is chosen so none of them require a redesign
  later — see **Cross-Platform Roadmap** section.
- **State**: Riverpod (or Bloc)
- **Rich text editor**: flutter_quill (or equivalent) — needs to support comments/highlights
  anchored to text ranges, and inline reference tags
- **Drive integration**: google_sign_in + googleapis (Dart) drive/v3, scoped to `drive.file` only
  (app can see only what it creates — not the whole Drive)
- **Storage**: local files (JSON + Markdown), no embedded database required for v1

## Data model (file-based, portable)

Top level: `Imaginaity/_GlobalIdeas/`, standalone `Imaginaity/<ProjectName>/`, and series-grouped
`Imaginaity/<SeriesName>/series.json` + `_shared/` (characters, worldbuilding, relationships,
timelines) + one `<BookName>/` per book — see Series Support section below for full structure.

```
Imaginaity/<ProjectName>/     # single project structure (also used per-book inside a series)
  project.json              # title, author, created/modified, settings
  todos/
    todos.json               # [{id, text, done, linkedSceneId?, priority, dueDate?}]
  manuscript/
    act-01/
      chapter-01/
        scene-01.json        # {title, content (markdown), pov, wordCountGoal, labels, linkedReferences}
        scene-02.json
      chapter-02/
    act-02/
    prologue.json            # {type: "prologue"|"epilogue"|"dedication"|"authorsNote", content, position: "front"|"back"}
    epilogue.json
  plot-grid/
    plotlines.json           # [{id, name, color}]
    plotpoints.json          # [{plotlineId, sceneId, title, notes, order}]
  characters/
    char-<id>.json           # {id, name, quickRef: [field names], fields: {...}, image}
  worldbuilding/
    entry-<id>.json          # same quickRef pattern as characters
  notes/
    note-<id>.json           # sticky notes/comments, {sceneId, textRange, body}
  timelines/
    timeline-<id>.json       # {id, name}
    event-<id>.json          # {timelineId, label, date/relativeTime, linkedSceneIds, linkedCharacterIds, linkedWorldIds}
  relationships/
    relationship-<id>.json   # {characterAId, characterBId, type, label, position: {x,y}}
  goals/
    goals.json                # goal definitions + dailyLog (see Goal Engine below)
  assets/
    covers/, images/
  .sync/
    manifest.json             # per-file hash + modifiedTime, for Drive conflict detection
```

Scene content stored as Markdown with light front-matter — readable and recoverable outside the
app, diff-friendly for sync conflicts. Character/world entries reference each other and scenes by
id, not by embedding full text, so the Reference Panel can pull just the fields it needs.

## Feature: Reference Panel (differentiator)

Dockable, resizable, collapsible side panel showing worldbuilding/character info **while writing**
— never forces a navigation away from the manuscript.

**Triggers:**
1. `@mention` autocomplete while typing inserts a lightweight tag (`[[char:elena-vance]]`), not
   full text; clicking/hovering the tag opens the panel to that entry
2. Optional auto-detect: matches known names in the current scene text and surfaces them
   (opt-in, to avoid false positives on common words)
3. Manual pin from the sidebar tree — stays visible regardless of what scene you're in
4. Scene-level `linkedReferences` list — panel auto-populates whenever that scene is open

**Panel behavior:**
- Compact cards showing only fields marked `quickRef` on that character/entry (author curates
  what's "at a glance" vs full profile)
- Multiple pinned/linked entries stack as scrollable cards
- Inline quick-edit (expand a field to edit without leaving the editor)
- Android: slide-over panel instead of docked (screen space)

## Feature: App Shell Basics — Dark Mode, Undo/Redo (table stakes)

**Dark mode:** light/dark theme toggle across the entire app shell (editor, panels, Reference
Panel, dialogs), follows system theme by default with manual override.

**Undo/redo:** standard fine-grained, in-session, keystroke-level undo/redo stack (Ctrl+Z/Ctrl+Y)
in the editor. Distinct from Version History (Phase 1.7), which is coarse-grained and persists
across sessions — the two serve different purposes and both are needed.

## Feature: Manuscript Structure & Formatting (table stakes)

**Prologues/epilogues/front-back matter:** special section types (`prologue`, `epilogue`,
`dedication`, `authorsNote`) that sit outside normal act/chapter numbering — fixed position
(before Act 1 / after final act), excluded from "Chapter N" auto-numbering, but included in word
totals and export.

**Formatting tools:** bold/italic/underline/strikethrough, scene breaks (centered `***` or custom
glyph), block quotes, chapter/section heading styles (not just bold text), text alignment.

**Editing-view fonts:** small curated set of comfortable writing fonts (serif/monospace options),
adjustable size/line spacing — separate from export fonts.

**Publishing/export fonts:** curated list reflecting real conventions — Times New Roman/Courier
12pt double-spaced for manuscript-submission format, Georgia/Garamond for print-style export,
a clean sans option for ebook body text. Curated list, not full system-font access. Fonts must be
embeddable (required for KDP print PDFs — see Export section).

**Metadata:** project gets `subtitle` (alongside `title`), and optionally `series`/`bookNumber` if
series support is ever wanted — flows through to cover, title page, and exports.

**Covers & in-book images:** cover image (`assets/covers/`) displayed in the project library view
and export title page. In-book images (`assets/images/`) attachable to a scene/chapter (chapter
art, maps), referenced by id from scene content, rendered inline in editor and carried through to
export.

## Feature: AI/External Review Round-Trip (differentiator)

Export a scene/chapter/manuscript in a stable-anchored format so an external reviewer — an LLM
(e.g. Claude) or a human beta reader — can return structured comments that re-attach to the exact
right spot in the live manuscript, using the same anchor mechanism as in-app comments/highlights.

**Export format:** Markdown (or JSON) with a stable anchor id per paragraph, e.g.:
```markdown
<!-- id: scene-01-p003 -->
Elena stepped through the doorway, unsure of what she'd find.
```
Human-readable — usable with any reviewer, not just an AI.

**Comment format (response):** JSON mapping anchor id → comment text + optional category
(pacing, consistency, dialogue, continuity, prose, ...):
```json
{ "comments": [
  { "anchorId": "scene-01-p003", "text": "...", "category": "prose" }
] }
```

**Import:** re-attaches each comment to its anchor as a normal in-app comment (same panel/UI as
native comments). If the source text has changed since export (anchor no longer matches exactly),
falls back to nearest-paragraph matching and flags it "approximate placement — verify" rather than
silently misplacing or dropping the comment.

**Placement:** extension of the Phase 4 comment/highlight/footnote anchoring system plus an
export/import layer — not a separate phase.

## Feature: Spell Check, Thesaurus, Dictionary & Footnotes (table stakes, multi-language)

**Spell check:** Hunspell engine (LGPL/GPL/MPL, same one LibreOffice/Firefox/Chrome use), via
Dart FFI for consistent cross-platform behavior (Android's native OS spellcheck differs from
Windows desktop, so bundling directly avoids inconsistency). Ships with **en-GB (UK English) as
the default**, not US English. Additional language dictionaries (French, Spanish, German, ...)
and additional English variants (en-US, en-CA, en-AU, en-NZ, en-ZA) downloadable/enabled per
project via a language picker in settings, using the freely redistributable Hunspell `.dic`/`.aff`
files the open-source community already maintains (LibreOffice ships all these variants). Variant
picker set at project creation, default en-GB, changeable per project (e.g. a US-set novel).
Possible later stretch: flag mixed-variant spelling within a manuscript (e.g. "colour"/"color"
both present), not required for v1.

**Thesaurus + dictionary:** bundled Open English WordNet dataset (free, actively maintained fork
of Princeton WordNet) — synonyms, hypernyms/hyponyms, and definitions in one offline dataset, no
network dependency, instant lookups. English fully offline at launch; other languages added
incrementally as decent free datasets are found (WordNet-quality coverage outside English is
inconsistent) rather than promised uniformly on day one. Optional online fallback (e.g. Free
Dictionary API) for supplementary definitions when connected, never a hard dependency.

**Footnotes:** inline marker anchored to a text position in scene content — same anchor mechanism
as comments/highlights (Phase 4), so built alongside them rather than as a separate system.
Footnote body editable via inline popover. Export renders as numbered footnotes (page-bottom for
PDF, endnotes for EPUB/docx per format convention).

## Feature: Voice-to-Text Dictation (differentiator)

Dictation mode in the editor — toggle on, speech streams into the current cursor position as
normal text, integrating with existing formatting/undo/version history rather than being a
separate transcription tool.

**Platform approach:**
- Android: OS built-in `SpeechRecognizer` — free, works offline on modern Android with on-device
  model enabled
- Windows (v1): Vosk (open-source offline speech-to-text) via Dart FFI/plugin bridge, since Flutter
  has no first-class Windows dictation support
- Offline-capable on both v1 platforms where possible, consistent with the app's offline-first
  philosophy — avoids sending manuscript audio to a cloud API by default
- **Future (macOS/Linux/iOS, not v1):** Vosk also runs on macOS and Linux, so the desktop path
  extends to all three with the same FFI bridge, no new engine needed. iOS uses `SFSpeechRecognizer`
  (on-device since iOS 13), same family as the existing Android native-API approach — see
  Cross-Platform Roadmap.

**Voice commands:** basic dictation conventions — "new paragraph," "comma," "full stop," "new
line" — so output isn't one unpunctuated stream.

**Language awareness:** recognizes in the project's configured language/variant (en-GB default),
using the same language settings as spell check.

**Review flow:** dictated text visually marked (subtle highlight) until reviewed/accepted, since
fiction's unusual names/vocabulary trip up speech engines more than everyday text.

## Feature: Adaptive Goal Engine (differentiator)

Goals set per project/act/scene, as either a fixed word count or a deadline. Daily targets are
**computed dynamically**, not fixed at creation:

- `daily target = remaining words ÷ remaining working days` (recalculated each day)
- Missed/under-target days redistribute the shortfall across remaining days
- Over-target days reduce future daily targets
- Working calendar: recurring days-off + one-off exceptions (holidays, busy days)
- Starting word count auto-detected from existing manuscript so goals don't double-count

**UI:** setup wizard (scope → target type → deadline/count → working days → live preview),
progress ring for today vs overall, calendar heatmap of daily performance vs target, and a subtle
notice when a target has been recalculated.

## Feature: Version History (differentiator)

Auto snapshots + named checkpoints, per scene — not full git, kept simple and writer-friendly.

**Auto snapshots:**
- Triggered on save, debounced (~30s of no typing, or ~300 words changed, whichever first)
- Stored as a diff against the previous version, not a full copy — keeps storage light
- Scoped per-scene, matching the file-per-scene data model

**Named checkpoints:**
- Manual "Save checkpoint" at project or scene level, with a label (e.g. "First draft complete")
- Checkpoints are snapshots flagged as pinned — never pruned, shown distinctly in the history UI

**Pruning policy:**
- All auto-snapshots kept for 24–48h, then thinned as they age (hourly → daily → weekly)
- Named checkpoints kept forever

**UI:**
- Per-scene History view: timeline, word-count graph, diff between any two points, one-click
  restore (restoring creates a new snapshot rather than destructively overwriting — the restore
  itself is undoable)

**Data model:**
```
manuscript/act-01/chapter-01/scene-01.json
manuscript/act-01/chapter-01/scene-01.history/
  2026-07-13T09-12-00.diff.json        # auto-snapshot (diff + metadata)
  2026-07-13T14-30-00.checkpoint.json  # named checkpoint (label: "First draft")
```

**Interaction with Drive sync:** history logs sync too, so snapshot history travels across
devices. Also doubles as a cleaner alternative to the raw `.conflict-*` files in the sync design —
an incoming conflicting version can be treated as a new snapshot to diff/merge against, using the
same history UI rather than a separate mechanism.

## Feature: Per-Project To-Do List (table stakes)

Flat/lightly-categorized task list scoped to a project — distinct from Version History (edit
history) and Global Ideas (raw concept capture); todos are actionable items.

- Optional linking to a scene/chapter/character (click → jump there), same pattern as comments
  and timeline events
- States: open/done, optional priority, optional due date

```json
{ "todos": [
  { "id": "todo-01", "text": "Fix Elena's eye colour inconsistency", "done": false,
    "linkedSceneId": "scene-04", "priority": "high" }
] }
```

## Feature: Multi-Novel Series Support (differentiator)

Groups multiple book-projects into a series, sharing characters/worldbuilding while keeping each
book's manuscript, plot grid, and todos independent.

**Shared at series level:** Characters, Worldbuilding entries, Relationship diagram, optional
series-wide Timeline spanning all books.

**Per-book (unchanged from single-project structure):** manuscript, Plot Grid, todos, goals,
version history.

**Folder structure:**
```
Imaginaity/
  _GlobalIdeas/
  <SeriesName>/
    series.json              # {title, description, order: [projectIds], cover}
    _shared/
      characters/
      worldbuilding/
      relationships/
      timelines/
    <Book1Name>/              # normal project structure
    <Book2Name>/
  <StandaloneProjectName>/    # non-series projects unaffected
```

A standalone project is effectively a series of one, so this is an optional grouping layer, not a
separate code path. A character used in a later book pulls from the shared pool but can carry
book-specific notes as an extension of the core profile, not a fork of it.

**Series dashboard:** browse all books, jump between them, view shared characters/world at a
glance, aggregate word counts/goals across the whole series.

## Feature: Global Ideas (differentiator)

A capture space outside any single novel project — for ideas that don't have a home yet.

**Structure:** lives at the app root, alongside (not inside) project folders:
```
Imaginaity/
  _GlobalIdeas/
    idea-<id>.json     # {title, body (markdown), tags, type, created, status, linkedProjectId?}
  <ProjectName>/
```

**Entry:** freeform title + Markdown body, optional tags (character, plot twist, title,
worldbuilding, random, ...), optional attached image/link. No forced categorization — quick
capture matters more than structure.

**Capture flow:** global "New Idea" action available anywhere in the app, not just inside a
project — quick-capture modal, minimal friction.

**Browsing:** flat, searchable, filterable-by-tag list for v1 (boards/graph views are a possible
later enhancement, not required).

**Promotion path:**
- Promote to new project — idea body seeds the new project's initial notes/premise
- Attach to existing project — pulled into that project's Story Notes/Worldbuilding/Characters
- Promoted/attached ideas are marked "used," not deleted, to keep the origin trail

**Sync:** `_GlobalIdeas` syncs via the same Drive mechanism as projects, as its own folder — ideas
need to be available across Windows and Android for capture-anywhere to be useful.

## Feature: Timeline Page (differentiator)

In-story chronology view — distinct from the Plot Grid (structural/manuscript order) and distinct
from Version History (real-world edit history). Tracks **when things happen in the story**, which
often isn't the same as manuscript order (flashbacks, multiple POV timelines, non-linear
narratives).

- **Multiple parallel tracks** — e.g. one per POV character, or "main" vs "backstory" — toggleable
  and overlayable on one view
- **Events**: date or relative-time marker, linked to the scene(s) where they occur (click →
  jump to scene), optionally linked to characters and world entries
- Feeds the Reference Panel — an event card can display like a character/world card

## Feature: Family Tree / Relationship Diagram (differentiator)

Visual relationship mapping between characters — broader than strictly "family": also romantic,
rivalry, allegiance, mentor, etc.

- Nodes = characters (pulled from existing Character Profiles), edges = relationship type + label
- Editable canvas: drag to position, draw a connection, pick relationship type from a preset set
  plus custom label
- Can surface a mini relationship view in the Reference Panel when viewing a character

## Feature: Automatic Table of Contents (table stakes)

Generated from chapter/section headings and front/back matter positions already in the data model
— no manual maintenance. Shown in-app as a dedicated navigation view, and generated into exported
docx/PDF/EPUB with proper heading-based navigation (EPUB needs a well-formed nav document — this
is directly useful for Phase 6 export quality).

## Feature: Export (table stakes + differentiator)

**General export:**
- **PDF** — full fidelity: images, formatting, fonts, page layout
- **DOCX** — full fidelity, editable in Word
- **Plain text (.txt)** — explicit stripped-down option; export dialog must warn that images and
  special formatting are excluded, so it's never a surprise

**Kindle/KDP-ready export (differentiator):** split into ebook and print paths, since KDP treats
them very differently and a single generic "Kindle export" would produce invalid submissions.

*Ebook (Kindle e-reader):*
- Format: **EPUB** (KDP's current standard; MOBI is deprecated and Amazon converts from EPUB
  automatically)
- Reflowable text, proper heading structure feeding the EPUB nav document (reuses Automatic TOC),
  embedded cover, front matter in correct order (title page, copyright page template, dedication)
- Font embedding matters less here — Kindle readers control their own display font — so the
  publishing-font picker is print-focused primarily

*Print (KDP paperback/hardcover):*
- **Trim size presets** (dropdown, not free entry, to avoid invalid submissions): 5"×8", 5.25"×8",
  5.5"×8.5", 6"×9" (most common for novels), 6.14"×9.21", 6.69"×9.61", 7"×10", 8.5"×11"
- **Margin/gutter calculation**: automatic, scaled to estimated page count per KDP's rules (inside
  margin must grow with page count) — not left for the user to guess
- **Structure options**: single- vs double-sided (novels typically double-sided/mirrored margins),
  running headers (book title/chapter title alternating pages, toggleable), page numbering start
  point (front matter often unnumbered/roman, body starts at 1), bleed vs no-bleed
- **Output**: print-ready PDF with embedded fonts (KDP requirement), correct trim size + bleed box
  set in the PDF itself; **cover exported separately** as a wraparound PDF (front + spine + back)
  since KDP uploads print covers separately from interior — spine width auto-calculated from page
  count and paper type using KDP's published formula

**Data model:**
```json
// export-profile.json (per project, reusable presets)
{ "profiles": [
  { "id": "kdp-ebook", "type": "epub", "target": "kindle" },
  { "id": "kdp-print-6x9", "type": "print-pdf", "trimSize": "6x9", "doubleSided": true,
    "runningHeaders": true, "bleed": false }
] }
```

## Feature: Google Drive Sync

- OAuth, `drive.file` scope only
- One dedicated Drive folder (`Imaginaity/`), mirrors local project folder structure, auto-created
  on first sign-in
- File-level sync: compare `.sync/manifest.json` (local) against Drive's modifiedTime/md5Checksum
  - Changed on one side only → push/pull
  - Changed on both sides → keep both files (`scene-01.conflict-<device>-<timestamp>.json`),
    flagged in-app for manual merge rather than silently overwriting prose
- Offline-first: every save is local and immediate; sync is best-effort (manual "Sync now" +
  on-foreground background sync)

## Phases

| Phase | Scope |
|---|---|
| 0 | Project scaffold, data model, local file storage, create/open project, dark mode, app shell |
| 0.5 | Global Ideas — capture space, quick-capture modal, list/search/tag view, promotion path |
| 1 | Manuscript editor, act/chapter/scene tree with drag-reorder, Focus Mode, find & replace, undo/redo, prologue/epilogue/front-back matter, basic formatting tools, editing-view fonts, per-project todo list |
| 1.3 | Voice-to-text dictation — platform speech engines, voice commands, review-flow highlighting |
| 1.5 | Adaptive Goal Engine — data model, calculation logic, setup wizard, progress UI, heatmap |
| 1.7 | Version History — auto snapshots, named checkpoints, diff view, restore, pruning |
| 2 | Character profiles, Worldbuilding entries, Story Notes, `quickRef` field curation |
| 2.5 | Reference Panel — docking UI, `@mention` autocomplete + tags, pin/unpin, scene auto-populate |
| 3 | Plot Grid — plot lines, plot points, POV/color labels, linked to scenes |
| 3.5 | Timeline page (multi-track) + Family tree/relationship diagram |
| 4 | Comments, highlights, sticky notes, footnotes (shared anchor mechanism), text-to-speech, AI/external review export-import round-trip |
| 4.5 | Spell check (Hunspell, multi-language, en-GB default), thesaurus + dictionary (Open English WordNet) |
| 5 | Google Drive OAuth + sync engine + conflict UI (reuses Version History diff/restore for conflicts) |
| 6 | General export (PDF, DOCX, plain-text-with-warning), automatic Table of Contents, publishing fonts, subtitle/series metadata, cover + in-book image upload |
| 6.3 | KDP-ready export — ebook (EPUB) path, print (trim size presets, margin/gutter calc, running headers, wraparound cover with spine calc) |
| 6.5 | Multi-Novel Series Support — series entity, shared characters/worldbuilding/relationships/timeline, series dashboard |
| 7 (parked) | Co-authoring — **parked, not scoped for v1.** Real-time concurrent editing needs a different sync model entirely (CRDT/OT), distinct from the file-level Drive sync used everywhere else. Needs dedicated design thought before it's even phased in; revisit once the core app is solid. |

## Cross-Platform Roadmap (macOS, iOS, Linux — post-v1)

**Decision (2026-07-24):** v1 stays scoped to Windows + Android, exactly as planned above. macOS,
iOS, and Linux are explicitly **future targets, not v1 build/ship targets** — but the architecture
choices above were checked against all three so adding them later is a build-matrix/packaging
exercise, not a redesign. Summary of what changes per platform when that day comes:

| Area | Windows/Android (v1) | macOS | Linux | iOS |
|---|---|---|---|---|
| Core app (editor, data model, Riverpod, flutter_quill, export) | as planned | no change — Flutter native | no change — Flutter native | no change — Flutter native |
| Voice dictation | Vosk (Win) / native SpeechRecognizer (Android) | Vosk (same FFI bridge as Windows) | Vosk (same FFI bridge) | `SFSpeechRecognizer` (native, on-device, same family as Android's approach) |
| Spell check (Hunspell via FFI) | compiled binary per-arch | compiled binary per-arch | compiled binary per-arch | compiled binary per-arch |
| Google Drive sync (`google_sign_in`) | officially supported | officially supported | **weak/unofficial support** — likely needs manual OAuth device-flow or browser-redirect fallback | officially supported |
| Packaging | MSIX (Win) / Play Store AAB (Android) | notarized `.app`/DMG, optionally Mac App Store later | no single standard — Flatpak or AppImage for broadest reach | App Store / TestFlight |
| Build requirement | any machine with Flutter | **requires a Mac (Xcode) to build/sign** — cloud CI (Codemagic/GitHub Actions macOS runners) is the option if no local Mac | any machine with Flutter | **requires a Mac (Xcode) + Apple Developer Program ($99/yr)** — same cloud-CI option applies |

**Key implication:** iOS and macOS both require macOS build tooling. User doesn't currently own a
Mac; when these platforms are picked up, cloud macOS CI (e.g. Codemagic, GitHub Actions macOS
runners) is the planned route rather than local hardware — revisit at that time.

**Nothing in the v1 phase plan needs to change to keep this door open** — file-based storage,
Riverpod, flutter_quill, and the FFI-based Hunspell/Vosk approach were deliberately chosen for
portability. The one item worth flagging now: Google Drive sync design should not silently assume
`google_sign_in` "just works" everywhere — Linux is the outlier and may need its own auth flow
when that platform is scoped.

## Decisions made

- Windows packaging: **MSIX**
- Android distribution: **Play Store** (eventual goal, not necessarily v1 launch)
- v1 platform scope: **Windows + Android only**; macOS, iOS, Linux are future targets (see
  Cross-Platform Roadmap) — architecture kept portable but not built/shipped for v1
- Co-authoring (Phase 7): **parked** — needs its own design pass on sync architecture (CRDT/OT)
  before it's scoped; not part of the current build sequence

## Open questions / decisions still needed

- Export priority order for Phase 6 (docx first is easiest; PDF/EPUB need a formatting engine)
- Play Store readiness requirements (privacy policy, data safety form re: Drive scope, signing
  config for MSIX/AAB) — worth revisiting once core phases are closer to done
- Timing for picking up macOS/iOS/Linux — no date set; revisit once Windows+Android v1 is solid

## Status

Planning complete for Phases 0–6.5, Phase 7 parked pending separate design work. App name decided
(Narraity, 2026-07-24). Cross-platform roadmap confirmed 2026-07-24: v1 stays Windows + Android,
macOS/iOS/Linux are future targets with architecture kept portable (see Cross-Platform Roadmap).

**Build started 2026-07-24.** Flutter project scaffolded at `Development/Narraity` (org
`uk.aity`). **Phases 0, 0.5, and 1 are built and verified** — running on Windows desktop, 26
automated tests passing, `flutter analyze` clean:

- **Phase 0** — project scaffold, file-based data model (`project.json` + folder skeleton per the
  Data Model section), library screen (create/open project, grid view), dark/light/system theme
  with persistence, app shell.
- **Phase 0.5** — Global Ideas: quick-capture dialog (available from library and inside a
  project), `_GlobalIdeas/idea-<id>.json` storage, search + tag-filter list view, promote-to-new-
  project and attach-to-existing-project paths (idea marked "used", not deleted, keeping the
  origin trail — seeds a story note in the target project).
- **Phase 1** — manuscript editor: act/chapter/scene tree with drag-reorder (scenes), add/delete
  at every level, prologue/epilogue/dedication/author's-note front/back matter; scene editor with
  debounced autosave to Markdown+front-matter files, formatting toolbar (bold/italic/strike/scene
  break/quote/heading), undo/redo, Find & Replace, live word count; Focus Mode (Esc to exit);
  editing-view font/size/line-spacing settings (persisted); per-project to-do list.
- **Also added**: a global error logger (`lib/services/app_logger.dart`) catching Flutter
  framework errors, async errors, and uncaught exceptions to
  `Documents/Narraity/.logs/app.log` — not part of the original phase scope, added for easier
  debugging during development.
- **Environment note**: the installed Visual Studio (2026, v18) postdates Flutter 3.35.5's known
  CMake generator list, which hardcodes a fallback to VS 2019. Patched locally in the Flutter SDK
  copy (`packages/flutter_tools/lib/src/windows/visual_studio.dart`) to add the VS 18 → "Visual
  Studio 18 2026" mapping — `flutter upgrade` would need this reapplied.

Next: Phase 1.3 (voice-to-text dictation) or continue polishing Phase 1, per user direction.
