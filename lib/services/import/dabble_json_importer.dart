import 'dart:convert';

import '../../models/manuscript_import.dart';

/// Parses a Dabble project export (Settings → Export → Export Project as
/// JSON, *not* the separate full-account backup format some Dabble tooling
/// also produces — that one has no `state` key and is rejected here with a
/// clear error rather than silently mis-parsed).
///
/// Schema verified against five real exports rather than guessed: a
/// document is `{docId, state: {id, type: "novel", children, docs}}`, where
/// `docs` is a flat map keyed by doc id. `docs['manuscripts']` is a fixed
/// container whose `children` are book ids; a book's `children` are chapter
/// ids; a chapter's `children` are scene ids (always exactly 3 levels in
/// every sample checked — no nested chapters). Deleted content sits under
/// `docs['trash']` and was confirmed never double-referenced by a live
/// book/chapter's own `children`, so a plain top-down walk from
/// `manuscripts` naturally excludes it without extra filtering.
///
/// Scene prose is a Quill Delta (`body.content.ops`) — Dabble's own rich
/// text format, not Narraity's markdown-lite, so every op is converted:
/// `bold`/`italic`/`strike` map directly to `**`/`*`/`~~`; `blockquote` maps
/// to Narraity's own `> ` prefix; `list` (no native Narraity equivalent —
/// the scene editor has no list concept at all, see
/// `manuscript_service.dart`'s doc comment) becomes a plain `- `/`N. `
/// prefix instead of being dropped. `grammar` and `comment` attributes are
/// Dabble's own editor metadata (grammar-check results, comment-thread
/// markers) and carry no visible text — silently ignored. Scenes have no
/// title of their own in the export, so they're numbered "Scene N" by
/// position, matching how Dabble itself only auto-numbers scenes in its UI.
class DabbleJsonImporter {
  static List<ImportedNode> parse(String jsonString) {
    final dynamic json;
    try {
      json = jsonDecode(jsonString);
    } catch (error) {
      throw ImportParseException('Not valid JSON: $error');
    }

    if (json is! Map<String, dynamic> || json['state'] is! Map<String, dynamic>) {
      throw ImportParseException(
        'Not a Dabble *project* export (missing "state"). If this came from '
        'a full-account backup rather than Dabble\'s per-project "Export as JSON", '
        'that format isn\'t supported — export the individual project instead.',
      );
    }

    final state = json['state'] as Map<String, dynamic>;
    if (state['docs'] is! Map<String, dynamic>) {
      throw ImportParseException('Not a valid Dabble export: missing "state.docs"');
    }
    final docs = state['docs'] as Map<String, dynamic>;

    if (docs['manuscripts'] is! Map<String, dynamic>) {
      throw ImportParseException('Not a valid Dabble export: missing the manuscripts container');
    }
    final manuscripts = docs['manuscripts'] as Map<String, dynamic>;
    final bookIds = _stringList(manuscripts['children']);

    return bookIds.map((id) => _convertBook(docs, id)).toList();
  }

  static ImportedNode _convertBook(Map<String, dynamic> docs, String id) {
    final doc = docs[id] as Map<String, dynamic>? ?? const {};
    final chapterIds = _stringList(doc['children']);
    return ImportedNode(
      title: _titleOr(doc, 'Untitled Book'),
      typeLabel: 'Book',
      children: chapterIds.map((chapterId) => _convertChapter(docs, chapterId)).toList(),
    );
  }

  static ImportedNode _convertChapter(Map<String, dynamic> docs, String id) {
    final doc = docs[id] as Map<String, dynamic>? ?? const {};
    final sceneIds = _stringList(doc['children']);
    final children = <ImportedNode>[
      for (var i = 0; i < sceneIds.length; i++) _convertScene(docs, sceneIds[i], i + 1),
    ];
    return ImportedNode(title: _titleOr(doc, 'Untitled Chapter'), typeLabel: 'Chapter', children: children);
  }

  static ImportedNode _convertScene(Map<String, dynamic> docs, String id, int index) {
    final doc = docs[id] as Map<String, dynamic>?;
    final body = doc?['body'] as Map<String, dynamic>?;
    final content = body?['content'] as Map<String, dynamic>?;
    final ops = content?['ops'] as List<dynamic>? ?? const [];
    return ImportedNode(title: 'Scene $index', typeLabel: 'Scene', content: _deltaToMarkdown(ops));
  }

  static String _titleOr(Map<String, dynamic> doc, String fallback) {
    final title = doc['title'] as String?;
    return (title == null || title.trim().isEmpty) ? fallback : title;
  }

  static List<String> _stringList(Object? value) =>
      (value as List<dynamic>? ?? const []).cast<String>();

  /// Converts one scene's Quill Delta into Narraity's markdown-lite,
  /// line-joined content string. Quill's `\n` (whether its own standalone
  /// op or embedded inside a longer text insert) is the real block/line
  /// boundary; `{"br": true}` embeds are a *soft* break Dabble always pairs
  /// immediately before that real `\n` in practice (confirmed in the real
  /// samples: 127 of 128 occurrences), so they're skipped rather than
  /// treated as their own line break — treating both as breaks would double
  /// every paragraph gap.
  static String _deltaToMarkdown(List<dynamic> ops) {
    final lines = <String>[];
    final buffer = StringBuffer();
    var orderedCounter = 0;

    void appendRun(String text, Map<String, dynamic>? attrs) {
      if (text.isEmpty) return;
      final bold = attrs?['bold'] == true;
      final italic = attrs?['italic'] == true;
      final strike = attrs?['strike'] == true;
      if (bold) {
        buffer.write('**$text**');
      } else if (strike) {
        buffer.write('~~$text~~');
      } else if (italic) {
        buffer.write('*$text*');
      } else {
        buffer.write(text);
      }
    }

    void flushLine(Map<String, dynamic>? blockAttrs) {
      var line = buffer.toString();
      buffer.clear();
      final list = blockAttrs?['list'] as String?;
      if (blockAttrs?['blockquote'] == true) {
        line = '> $line';
        orderedCounter = 0;
      } else if (list == 'ordered') {
        orderedCounter++;
        line = '$orderedCounter. $line';
      } else if (list == 'bullet') {
        line = '- $line';
        orderedCounter = 0;
      } else {
        orderedCounter = 0;
      }
      lines.add(line);
    }

    for (final rawOp in ops) {
      final op = rawOp as Map<String, dynamic>;
      final insert = op['insert'];
      final attrs = op['attributes'] as Map<String, dynamic>?;

      if (insert is Map) {
        continue; // {"br": true} or an unsupported embed (e.g. an image) — no plain-text form.
      }

      final segments = (insert as String? ?? '').split('\n');
      for (var i = 0; i < segments.length; i++) {
        if (i > 0) flushLine(attrs);
        appendRun(segments[i], attrs);
      }
    }
    if (buffer.isNotEmpty) lines.add(buffer.toString());

    return lines.join('\n');
  }
}
