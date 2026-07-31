import '../../models/export_outline.dart';
import '../../models/manuscript.dart';

/// Reports progress through an export's *top-level* sections (Books/Acts/
/// front-matter items — whatever sits at depth 0) rather than every leaf
/// scene, since a top-level count is a stable, meaningful unit regardless of
/// how deep any one section's own subtree happens to be. [completed] is
/// 1-based and reaches [total] exactly once, right when the export finishes.
typedef ExportProgressCallback = void Function(int completed, int total);

/// Flattens a [ManuscriptStructure] into export reading order with each
/// section's nesting depth — pure and synchronous (no file I/O; scene
/// *content* is read separately per id by whichever format is exporting),
/// so it's trivially unit-testable and has exactly one implementation for
/// every export format to share.
class ManuscriptOutlineBuilder {
  /// Freeform `typeLabel`s (case-insensitive) treated as a real chapter-level
  /// division regardless of depth — covers every shape `manuscript_seeds.dart`
  /// offers (Act, Chapter, Book/Part are all used as either the top level or
  /// nested one level under another container), so e.g. Book > Chapter still
  /// breaks between chapters, not just once at the Book level.
  static const _chapterLikeLabels = {'chapter', 'chapters', 'act', 'acts', 'book', 'books', 'part', 'parts'};

  static bool _isChapterBoundary(ManuscriptNode node, int depth) =>
      depth == 0 || _chapterLikeLabels.contains(node.typeLabel.trim().toLowerCase());

  static List<ExportSection> build(ManuscriptStructure structure) {
    final sections = <ExportSection>[];

    for (final section in structure.frontMatter) {
      sections.add(ExportSection(
        id: section.id,
        title: section.title,
        depth: 0,
        kind: ExportSectionKind.frontMatter,
      ));
    }

    void walk(List<ManuscriptNode> nodes, int depth) {
      for (final node in nodes) {
        sections.add(ExportSection(
          id: node.id,
          title: node.title,
          depth: depth,
          kind: ExportSectionKind.node,
          showTitle: node.showTitleInExport,
          startsNewPage: _isChapterBoundary(node, depth),
        ));
        walk(node.children, depth + 1);
      }
    }

    walk(structure.nodes, 0);

    for (final section in structure.backMatter) {
      sections.add(ExportSection(
        id: section.id,
        title: section.title,
        depth: 0,
        kind: ExportSectionKind.backMatter,
      ));
    }

    return sections;
  }
}
