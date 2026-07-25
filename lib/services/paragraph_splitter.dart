/// Splits scene content into paragraphs for the AI/external review round-trip
/// export (Phase 4). A paragraph is a block of one or more non-blank lines;
/// blank lines (one or more) separate paragraphs. Pure/no Flutter
/// dependency, matching `mention_scanner.dart`'s "keep the parsing
/// unit-testable" precedent.
library;

class Paragraph {
  const Paragraph({required this.index, required this.start, required this.end, required this.text});

  /// Zero-based order within the scene.
  final int index;

  /// `[start, end)` character range in the *original* content string —
  /// exactly what a `TextAnchor` needs.
  final int start;
  final int end;
  final String text;
}

final _paragraphPattern = RegExp(r'[^\n]+(?:\n[^\n]+)*');

List<Paragraph> splitParagraphs(String content) {
  final paragraphs = <Paragraph>[];
  var index = 0;
  for (final match in _paragraphPattern.allMatches(content)) {
    final text = match.group(0)!;
    if (text.trim().isEmpty) continue;
    paragraphs.add(Paragraph(index: index, start: match.start, end: match.end, text: text));
    index++;
  }
  return paragraphs;
}
