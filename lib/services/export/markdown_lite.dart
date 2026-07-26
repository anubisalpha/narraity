/// A run of text with the same inline styling — the smallest unit every
/// export format renders (a styled text span in DOCX/PDF/EPUB).
class MdRun {
  const MdRun(this.text, {this.bold = false, this.italic = false, this.strikethrough = false});

  final String text;
  final bool bold;
  final bool italic;
  final bool strikethrough;
}

enum MdBlockType { paragraph, heading, quote, sceneBreak }

/// One block-level unit of parsed scene content. [lines] holds one entry per
/// literal source line (a scene is a plain multi-line text field, not a
/// rich-paragraph editor, so a writer's own line breaks — dialogue
/// formatting, verse — are preserved rather than collapsed into a single
/// run-on paragraph). A heading/scene-break has at most one line.
class MdBlock {
  const MdBlock({required this.type, this.headingLevel = 0, this.lines = const []});

  final MdBlockType type;

  /// 1-6, meaningful only when [type] is [MdBlockType.heading].
  final int headingLevel;

  final List<List<MdRun>> lines;
}

/// Parses the scene editor's markdown-subset formatting (see
/// `scene_editor.dart`'s toolbar: `**bold**`, `*italic*`, `~~strikethrough~~`,
/// `## heading`, `> quote`, and a `***` scene break) into a block/run
/// structure every export format (TXT/DOCX/PDF/EPUB) renders from — so the
/// parsing logic exists exactly once, not reimplemented per format.
class MarkdownLite {
  static final _inlinePattern = RegExp(r'\*\*(.+?)\*\*|~~(.+?)~~|\*(.+?)\*');
  static final _headingPattern = RegExp(r'^(#{1,6})\s+(.*)$');

  static List<MdBlock> parse(String content) {
    final blocks = <MdBlock>[];
    var paragraphLines = <List<MdRun>>[];
    var quoteLines = <List<MdRun>>[];

    void flushParagraph() {
      if (paragraphLines.isNotEmpty) {
        blocks.add(MdBlock(type: MdBlockType.paragraph, lines: paragraphLines));
        paragraphLines = [];
      }
    }

    void flushQuote() {
      if (quoteLines.isNotEmpty) {
        blocks.add(MdBlock(type: MdBlockType.quote, lines: quoteLines));
        quoteLines = [];
      }
    }

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) {
        flushParagraph();
        flushQuote();
        continue;
      }

      final headingMatch = _headingPattern.firstMatch(line);
      if (headingMatch != null) {
        flushParagraph();
        flushQuote();
        blocks.add(MdBlock(
          type: MdBlockType.heading,
          headingLevel: headingMatch.group(1)!.length,
          lines: [parseInline(headingMatch.group(2)!)],
        ));
        continue;
      }

      if (line.trim() == '***') {
        flushParagraph();
        flushQuote();
        blocks.add(const MdBlock(type: MdBlockType.sceneBreak));
        continue;
      }

      if (line.startsWith('> ')) {
        flushParagraph();
        quoteLines.add(parseInline(line.substring(2)));
        continue;
      }

      flushQuote();
      paragraphLines.add(parseInline(line));
    }
    flushParagraph();
    flushQuote();
    return blocks;
  }

  /// Parses one line's inline styling. Delimiters don't nest (a bold span's
  /// own text is never re-scanned for italics inside it) — matches what the
  /// editor's toolbar actually produces, which never combines markers.
  static List<MdRun> parseInline(String text) {
    final runs = <MdRun>[];
    var lastEnd = 0;
    for (final match in _inlinePattern.allMatches(text)) {
      if (match.start > lastEnd) {
        runs.add(MdRun(text.substring(lastEnd, match.start)));
      }
      final bold = match.group(1);
      final strike = match.group(2);
      final italic = match.group(3);
      if (bold != null) {
        runs.add(MdRun(bold, bold: true));
      } else if (strike != null) {
        runs.add(MdRun(strike, strikethrough: true));
      } else if (italic != null) {
        runs.add(MdRun(italic, italic: true));
      }
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      runs.add(MdRun(text.substring(lastEnd)));
    }
    if (runs.isEmpty) runs.add(MdRun(text));
    return runs;
  }
}
