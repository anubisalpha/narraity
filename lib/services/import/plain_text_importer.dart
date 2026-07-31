import '../../models/manuscript_import.dart';
import 'import_tree_builder.dart';

/// Parses plain text or Markdown into an [ImportedNode] tree. Recognizes
/// exactly the same conventions Narraity's own scene editor and export
/// pipeline use (see `markdown_lite.dart`): `# ` .. `###### ` lines as
/// headings (depth = level - 1) and a lone `***` line as a scene break.
/// Anything else is body content, passed through unchanged since it's
/// already compatible with the markdown-lite dialect scenes are stored in
/// (`**bold**`, `*italic*`, `~~strike~~`, `> quote`).
class PlainTextImporter {
  static final _headingPattern = RegExp(r'^(#{1,6})\s+(.*)$');

  static List<ImportedNode> parse(String text) {
    final events = <ImportEvent>[];
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trimRight().replaceAll('\r', '');
      final headingMatch = _headingPattern.firstMatch(line);
      if (headingMatch != null) {
        events.add(HeadingEvent(headingMatch.group(2)!.trim(), headingMatch.group(1)!.length - 1));
        continue;
      }
      if (line.trim() == '***') {
        events.add(const SceneBreakEvent());
        continue;
      }
      events.add(BodyLineEvent(line));
    }
    return buildImportTree(events);
  }
}
