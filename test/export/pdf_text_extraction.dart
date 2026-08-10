import 'dart:convert';

/// Extracts human-readable text from an *uncompressed* PDF (`compressPdf:
/// false`) produced by this app's exporters.
///
/// Embedding a real Unicode font (`PdfFonts`) moved every text-show operator
/// from literal WinAnsi `(text) Tj` strings to Identity-H `<hex> Tj` CID
/// glyph-index strings — a plain `(...)` regex no longer finds anything, and
/// the raw glyph codes are meaningless without resolving them back through
/// whichever font was active at that point in the stream (`/Fx size Tf`),
/// via that font's own embedded `/ToUnicode` CMap. This walks each content
/// stream token-by-token tracking the active font, decoding every `<hex>`
/// operand through the right CMap.
List<String> perPageDecodedText(List<int> bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  final cmaps = _parseCmaps(text);
  final fontToCmap = _fontToCmapObj(text);
  final resourceToFont = _resourceNameToFontObj(text);

  final streams =
      RegExp(r'stream\r?\n([\s\S]*?)endstream').allMatches(text).map((m) => m.group(1)!);
  // A real text-show operator is always immediately preceded by its closing
  // delimiter (`>` for a hex string, `]` for a TJ array) — a bare
  // `contains('Tj')` check is too loose and false-positives on embedded font
  // program streams (hundreds of KB of near-random ASCII85 data, likely to
  // contain that two-character substring purely by chance), which would
  // otherwise get miscounted as extra, empty "pages" and shift every real
  // page's index.
  return streams.where((s) => RegExp(r'>\s*Tj|\]\s*TJ').hasMatch(s)).map((s) {
    return _decodeContentStream(s, resourceToFont, fontToCmap, cmaps);
  }).toList();
}

/// Every page's decoded text joined into one blob — a value split across
/// adjacent kerned `TJ` array entries (or across a page boundary) can still
/// be found via `contains`, without needing exact per-page reconstruction.
String allDecodedText(List<int> bytes) => perPageDecodedText(bytes).join();

/// Parses every `N 0 obj ... begincmap ... endcmap` block into a
/// {cmap object number: {glyph code: decoded string}} map. A `ToUnicode`
/// CMap's `beginbfchar`/`endbfchar` section maps single codes 1:1;
/// `beginbfrange`/`endbfrange` maps a contiguous code range to a
/// contiguous destination range (or, in the `[...]` array form, one
/// explicit destination per code — not needed here since the `pdf` package
/// only emits the single-run range form).
Map<int, Map<int, String>> _parseCmaps(String text) {
  final cmaps = <int, Map<int, String>>{};
  for (final obj in RegExp(r'(\d+) 0 obj([\s\S]*?)endobj').allMatches(text)) {
    final body = obj.group(2)!;
    if (!body.contains('begincmap')) continue;
    final objNum = int.parse(obj.group(1)!);
    final map = <int, String>{};

    for (final m
        in RegExp(r'beginbfchar([\s\S]*?)endbfchar').allMatches(body)) {
      for (final pair
          in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>').allMatches(m.group(1)!)) {
        map[int.parse(pair.group(1)!, radix: 16)] = _hexToUnicode(pair.group(2)!);
      }
    }
    for (final m
        in RegExp(r'beginbfrange([\s\S]*?)endbfrange').allMatches(body)) {
      for (final triple in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')
          .allMatches(m.group(1)!)) {
        final start = int.parse(triple.group(1)!, radix: 16);
        final end = int.parse(triple.group(2)!, radix: 16);
        final destStart = int.parse(triple.group(3)!, radix: 16);
        for (var code = start; code <= end; code++) {
          map[code] = String.fromCharCode(destStart + (code - start));
        }
      }
    }
    cmaps[objNum] = map;
  }
  return cmaps;
}

/// A ToUnicode destination is UTF-16BE hex, usually one 4-hex-digit
/// codepoint but occasionally a surrogate pair or multi-char string.
String _hexToUnicode(String hex) {
  final units = <int>[];
  for (var i = 0; i + 4 <= hex.length; i += 4) {
    units.add(int.parse(hex.substring(i, i + 4), radix: 16));
  }
  return String.fromCharCodes(units);
}

/// Maps each font object number to the object number of its own
/// `/ToUnicode N 0 R` CMap.
Map<int, int> _fontToCmapObj(String text) {
  final map = <int, int>{};
  for (final obj in RegExp(r'(\d+) 0 obj([\s\S]*?)endobj').allMatches(text)) {
    final m = RegExp(r'/ToUnicode (\d+) 0 R').firstMatch(obj.group(2)!);
    if (m != null) {
      map[int.parse(obj.group(1)!)] = int.parse(m.group(1)!);
    }
  }
  return map;
}

/// Maps each resource name (e.g. `F1`) to the font object number it points
/// at, from every `/Font<</F1 5 0 R .../>>` resource dictionary in the
/// document — fonts are shared objects reused across pages in this app's
/// output, so one global scrape covers every page's resource dictionary.
Map<String, int> _resourceNameToFontObj(String text) {
  final map = <String, int>{};
  for (final dict in RegExp(r'/Font<<((?:/\w+ \d+ 0 R)+)>>').allMatches(text)) {
    for (final entry in RegExp(r'/(\w+) (\d+) 0 R').allMatches(dict.group(1)!)) {
      map[entry.group(1)!] = int.parse(entry.group(2)!);
    }
  }
  return map;
}

/// Walks one content stream in order, tracking the active font through
/// `/Fx size Tf` and decoding every `<hex>` operand of a `Tj` or `TJ`
/// through that font's CMap. Text between mismatched/unmapped codes is
/// simply skipped rather than throwing — good enough for test assertions
/// that only check `contains`, and tolerant of any operator this simple
/// tokenizer doesn't specifically understand.
String _decodeContentStream(
  String stream,
  Map<String, int> resourceToFont,
  Map<int, int> fontToCmap,
  Map<int, Map<int, String>> cmaps,
) {
  final buffer = StringBuffer();
  Map<int, String>? activeCmap;

  final tokenPattern = RegExp(
    r'/(\w+)\s+[\d.]+\s+Tf'
    r'|<((?:[0-9A-Fa-f]{2})+)>\s*Tj'
    r'|\[((?:<(?:[0-9A-Fa-f]{2})+>|-?[\d.]+|\s)*)\]\s*TJ',
  );

  String decodeHex(String hex) {
    final cmap = activeCmap;
    if (cmap == null) return '';
    final out = StringBuffer();
    for (var i = 0; i + 4 <= hex.length; i += 4) {
      final code = int.parse(hex.substring(i, i + 4), radix: 16);
      final ch = cmap[code];
      if (ch != null) out.write(ch);
    }
    return out.toString();
  }

  for (final m in tokenPattern.allMatches(stream)) {
    if (m.group(1) != null) {
      final fontObj = resourceToFont[m.group(1)];
      final cmapObj = fontObj == null ? null : fontToCmap[fontObj];
      activeCmap = cmapObj == null ? null : cmaps[cmapObj];
    } else if (m.group(2) != null) {
      buffer.write(decodeHex(m.group(2)!));
    } else if (m.group(3) != null) {
      for (final h in RegExp(r'<((?:[0-9A-Fa-f]{2})+)>').allMatches(m.group(3)!)) {
        buffer.write(decodeHex(h.group(1)!));
      }
    }
  }
  return buffer.toString();
}
