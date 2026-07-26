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
  });

  final String id;
  final String title;

  /// 0 for a top-level manuscript node (or any front/back matter section);
  /// increases by 1 per nesting level for child nodes. Formats map this to
  /// heading levels (H1/H2/... in DOCX/EPUB, font size step in PDF).
  final int depth;

  final ExportSectionKind kind;
}
