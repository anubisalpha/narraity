import '../../models/export_outline.dart';
import '../../models/manuscript.dart';

/// Flattens a [ManuscriptStructure] into export reading order with each
/// section's nesting depth — pure and synchronous (no file I/O; scene
/// *content* is read separately per id by whichever format is exporting),
/// so it's trivially unit-testable and has exactly one implementation for
/// every export format to share.
class ManuscriptOutlineBuilder {
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
