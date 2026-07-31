import '../../models/manuscript_import.dart';

/// One normalized event from a source document, in document order — both
/// the plain-text/markdown importer and the DOCX importer reduce their very
/// different source formats down to this same stream, so the actual
/// tree-building logic (this file) exists exactly once.
sealed class ImportEvent {
  const ImportEvent();
}

/// A heading at [depth] (0 = top-level chapter/section).
class HeadingEvent extends ImportEvent {
  const HeadingEvent(this.title, this.depth);
  final String title;
  final int depth;
}

/// A scene break within the current node's own prose.
class SceneBreakEvent extends ImportEvent {
  const SceneBreakEvent();
}

/// One line of body content, already in Narraity's markdown-lite dialect.
class BodyLineEvent extends ImportEvent {
  const BodyLineEvent(this.line);
  final String line;
}

/// Generic type labels by depth — a plain heading has no way to say whether
/// it "means" Act/Chapter/Part, so this picks the two most common
/// conventions (top-level chapters, optional scene subdivisions) and falls
/// back to a generic label for anything deeper. Renamable after import like
/// any other node.
String _typeLabelForDepth(int depth) => switch (depth) {
      0 => 'Chapter',
      1 => 'Scene',
      _ => 'Section',
    };

/// Builds an [ImportedNode] tree from a flat event stream. A heading at
/// depth N becomes a new node nested N levels deep (popping/pushing a depth
/// stack as it goes); body lines and scene breaks accumulate onto whichever
/// node is currently deepest ("current"), matching how a real
/// [ManuscriptNode] holds its own prose *and* children at once — content
/// before a chapter's first subheading belongs to the chapter itself, not a
/// synthetic child.
///
/// Content that appears before the first heading gets an implicit "Chapter
/// 1" node so it isn't dropped; a document with no headings at all becomes
/// a single "Chapter 1" node holding everything.
List<ImportedNode> buildImportTree(List<ImportEvent> events) {
  final roots = <ImportedNode>[];
  // Stack of (depth, node) pairs from shallowest to deepest currently open.
  final stack = <(int, ImportedNode)>[];
  final currentLines = <int, List<String>>{}; // depth -> pending body lines for that node

  void flushLinesOnto(ImportedNode node) {
    final lines = currentLines.remove(stack.isEmpty ? -1 : stack.last.$1);
    if (lines != null && lines.isNotEmpty) {
      node.content = (node.content.isEmpty ? '' : '${node.content}\n')
          + lines.join('\n');
    }
  }

  void ensureImplicitChapter() {
    if (stack.isNotEmpty) return;
    final node = ImportedNode(title: 'Chapter 1', typeLabel: 'Chapter');
    roots.add(node);
    stack.add((0, node));
  }

  void appendLine(String line) {
    ensureImplicitChapter();
    final depth = stack.last.$1;
    currentLines.putIfAbsent(depth, () => []).add(line);
  }

  for (final event in events) {
    switch (event) {
      case HeadingEvent(:final title, :final depth):
        // Flush any pending body lines onto whatever was open at that depth
        // before popping down/up to the new heading's level.
        if (stack.isNotEmpty) flushLinesOnto(stack.last.$2);
        while (stack.isNotEmpty && stack.last.$1 >= depth) {
          stack.removeLast();
        }
        final node = ImportedNode(title: title, typeLabel: _typeLabelForDepth(depth));
        if (stack.isEmpty) {
          roots.add(node);
        } else {
          stack.last.$2.children.add(node);
        }
        stack.add((depth, node));

      case SceneBreakEvent():
        appendLine('***');

      case BodyLineEvent(:final line):
        appendLine(line);
    }
  }

  if (stack.isNotEmpty) flushLinesOnto(stack.last.$2);

  return roots;
}
