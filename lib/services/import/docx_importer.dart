import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../models/manuscript_import.dart';
import 'import_tree_builder.dart';

/// Parses a `.docx` (a zip of OOXML parts) into an [ImportedNode] tree.
/// Headings form the tree — nested arbitrarily deep, not just a fixed
/// Chapter/Scene pair: a `Heading1` is a top-level node, a `Heading2` right
/// after it becomes its child, another `Heading2` is a sibling under the
/// same `Heading1`, a `Heading3` nests one level deeper again, and so on
/// (see `import_tree_builder.dart`'s depth-stack logic, shared with the
/// plain-text importer).
///
/// Only reads `word/document.xml`'s top-level body paragraphs — content
/// inside tables isn't walked, and every namespace-qualified element is
/// matched by local name only (not full namespace), which holds up fine
/// against real-world `.docx` files from Word/LibreOffice/Google
/// Docs/Narraity's own exporter without needing to resolve their exact
/// namespace prefixes.
class DocxImporter {
  static List<ImportedNode> parse(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (error) {
      throw ImportParseException('Not a valid .docx (not a zip file): $error');
    }

    final documentFile = archive.files
        .where((f) => f.name == 'word/document.xml')
        .firstOrNull;
    if (documentFile == null) {
      throw ImportParseException('Not a valid .docx: missing word/document.xml');
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(utf8.decode(documentFile.content as List<int>));
    } catch (error) {
      throw ImportParseException('word/document.xml is not well-formed XML: $error');
    }

    final body = _descendantsLocal(document, 'body').firstOrNull;
    if (body == null) {
      throw ImportParseException('Not a valid .docx: missing document body');
    }

    final paragraphs = body.children.whereType<XmlElement>().where((e) => e.name.local == 'p');

    final events = <ImportEvent>[];
    for (final paragraph in paragraphs) {
      _emitParagraphEvents(paragraph, events);
    }
    return buildImportTree(events);
  }

  static void _emitParagraphEvents(XmlElement paragraph, List<ImportEvent> events) {
    final plainText = _plainText(paragraph).trim();

    if (plainText.isNotEmpty && _isSceneBreakText(plainText)) {
      events.add(const SceneBreakEvent());
      return;
    }

    final headingDepth = _headingDepth(paragraph);
    if (headingDepth != null) {
      if (plainText.isNotEmpty) {
        events.add(HeadingEvent(plainText, headingDepth));
      }
      return;
    }

    if (plainText.isEmpty) return;
    for (final line in _formattedLines(paragraph)) {
      events.add(BodyLineEvent(line));
    }
  }

  static bool _isSceneBreakText(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    return RegExp(r'^([*#~\-•])\1{2,}$').hasMatch(compact);
  }

  /// Word's built-in heading styles always use the styleId `Heading1`..
  /// `Heading9` (and `Title`/`Subtitle`) regardless of the document's
  /// display language — only the human-readable name is localized, not the
  /// id. Falls back to a direct-formatting heuristic (a single bold run at
  /// heading-sized text, no named style at all) so documents Narraity
  /// itself exported — which uses direct formatting rather than named
  /// styles, see `docx_exporter.dart` — round-trip correctly too.
  ///
  /// The fallback also requires the paragraph *not* be centered: a title
  /// page's title/subtitle/author lines are bold-and-large too (see
  /// `docx_exporter.dart`'s `_titlePageXml`) but are centered, while chapter
  /// headings there aren't — caught by an actual round-trip test importing
  /// our own export, which otherwise misread the title page as an extra
  /// top-level chapter. Trade-off: a document that centers its own
  /// direct-formatted chapter headings (no named style) won't be detected
  /// either — an acceptable miss next to wrongly inventing a phantom
  /// chapter from every title page.
  static int? _headingDepth(XmlElement paragraph) {
    final styleId = _styleId(paragraph);
    if (styleId != null) {
      final normalized = styleId.replaceAll(' ', '').toLowerCase();
      final headingMatch = RegExp(r'^heading(\d)$').firstMatch(normalized);
      if (headingMatch != null) {
        return (int.parse(headingMatch.group(1)!) - 1).clamp(0, 5);
      }
      if (normalized == 'title') return 0;
      if (normalized == 'subtitle') return 1;
    }

    final runs = _runs(paragraph).toList();
    if (runs.length == 1 && !_isCentered(paragraph)) {
      final run = runs.first;
      final rPr = _rPr(run);
      final bold = _isOn(rPr == null ? null : _childLocal(rPr, 'b'));
      final size = _fontHalfPoints(run);
      if (bold && size != null && size >= 24) {
        if (size >= 32) return 0;
        if (size >= 28) return 1;
        return 2;
      }
    }
    return null;
  }

  /// Converts one paragraph's runs into Narraity's markdown-lite dialect
  /// (`**bold**`, `*italic*`, `~~strike~~`), splitting into multiple lines
  /// on an explicit `<w:br/>` (a manual line break within one Word
  /// paragraph — poetry, address blocks). Every paragraph produces at least
  /// one line.
  static List<String> _formattedLines(XmlElement paragraph) {
    final lines = <String>[];
    final buffer = StringBuffer();

    void wrapAndAppend(String text, {required bool bold, required bool italic, required bool strike}) {
      if (text.isEmpty) return;
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

    for (final run in _runs(paragraph)) {
      final rPr = _rPr(run);
      final bold = _isOn(rPr == null ? null : _childLocal(rPr, 'b'));
      final italic = _isOn(rPr == null ? null : _childLocal(rPr, 'i'));
      final strike = _isOn(rPr == null ? null : _childLocal(rPr, 'strike'));

      for (final child in run.children.whereType<XmlElement>()) {
        switch (child.name.local) {
          case 't':
            wrapAndAppend(child.innerText, bold: bold, italic: italic, strike: strike);
          case 'tab':
            buffer.write('\t');
          case 'br':
            lines.add(buffer.toString());
            buffer.clear();
        }
      }
    }
    lines.add(buffer.toString());
    return lines;
  }

  // ---- low-level XML helpers (local-name matching, namespace-agnostic) ----

  static Iterable<XmlElement> _descendantsLocal(XmlNode node, String local) =>
      node.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

  static XmlElement? _childLocal(XmlElement el, String local) {
    for (final c in el.children.whereType<XmlElement>()) {
      if (c.name.local == local) return c;
    }
    return null;
  }

  static String? _attr(XmlElement el, String local) {
    for (final a in el.attributes) {
      if (a.name.local == local) return a.value;
    }
    return null;
  }

  static String? _styleId(XmlElement paragraph) {
    final pPr = _childLocal(paragraph, 'pPr');
    final pStyle = pPr == null ? null : _childLocal(pPr, 'pStyle');
    return pStyle == null ? null : _attr(pStyle, 'val');
  }

  static bool _isCentered(XmlElement paragraph) {
    final pPr = _childLocal(paragraph, 'pPr');
    final jc = pPr == null ? null : _childLocal(pPr, 'jc');
    return jc != null && _attr(jc, 'val') == 'center';
  }

  static Iterable<XmlElement> _runs(XmlElement paragraph) => _descendantsLocal(paragraph, 'r');

  static XmlElement? _rPr(XmlElement run) => _childLocal(run, 'rPr');

  /// Word/OOXML toggle properties (`<w:b/>`, `<w:i/>`, `<w:strike/>`) are
  /// "on" just by being present; `<w:b w:val="0"/>` (or "false") explicitly
  /// turns them back off — matters for inherited-then-cleared formatting.
  static bool _isOn(XmlElement? toggle) {
    if (toggle == null) return false;
    final val = _attr(toggle, 'val');
    if (val == null) return true;
    return val != '0' && val.toLowerCase() != 'false';
  }

  static int? _fontHalfPoints(XmlElement run) {
    final rPr = _rPr(run);
    final sz = rPr == null ? null : _childLocal(rPr, 'sz');
    final val = sz == null ? null : _attr(sz, 'val');
    return val == null ? null : int.tryParse(val);
  }

  static String _plainText(XmlElement paragraph) =>
      _descendantsLocal(paragraph, 't').map((t) => t.innerText).join();
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
