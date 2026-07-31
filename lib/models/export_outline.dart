/// What kind of section an [ExportSection] represents — front/back matter
/// (prologue, dedication, epilogue, author's note) render without chapter
/// numbering; manuscript nodes render as the book's actual structure.
enum ExportSectionKind { frontMatter, node, backMatter }

/// One heading-and-content unit in export reading order — the flattened,
/// depth-aware view every export format (TXT/DOCX/PDF/EPUB) walks to build
/// its own output, so the "what order do sections come in, and how deep is
/// each heading" logic exists exactly once.
class ExportSection {
  const ExportSection({
    required this.id,
    required this.title,
    required this.depth,
    required this.kind,
    this.showTitle = true,
    this.startsNewPage = true,
  });

  final String id;
  final String title;

  /// 0 for a top-level manuscript node (or any front/back matter section);
  /// increases by 1 per nesting level for child nodes. Formats map this to
  /// heading levels (H1/H2/... in DOCX/EPUB, font size step in PDF).
  final int depth;

  final ExportSectionKind kind;

  /// Whether to print [title] as a heading above this section's prose.
  /// Mirrors `ManuscriptNode.showTitleInExport` — always true for front/back
  /// matter, which has no such toggle. Formats that need a title regardless
  /// (an EPUB section's `<head><title>`, e.g.) use [title] directly instead
  /// of gating on this.
  final bool showTitle;

  /// Whether this section is a genuine "chapter break" — always true for
  /// depth-0 sections (front/back matter, top-level nodes), and also true
  /// for any node whose freeform `typeLabel` reads as chapter/act/book/part
  /// regardless of depth (see `ManuscriptOutlineBuilder._chapterLikeLabels`).
  /// A book structured as a single top-level "Book" node wrapping many
  /// "Chapter" children (all at depth 1) still needs page/file breaks
  /// between chapters, not just once at depth 0 — hence checking typeLabel
  /// too, not depth alone. Plain leaf content (Scene, depth 2+) is false,
  /// so consecutive scenes flow together instead of each forcing a new
  /// page/EPUB file.
  final bool startsNewPage;
}
