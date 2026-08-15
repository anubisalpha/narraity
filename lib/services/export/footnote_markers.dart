import '../../models/annotation.dart';
import '../annotation_service.dart';

/// Shared footnote-marker scheme used by every export format that supports
/// footnotes (EPUB, DOCX, PDF): a Private-Use-Area character pair wraps a
/// footnote's number, inserted into a scene's raw markdown *before* it's
/// parsed — never appears in real user content, and isn't one of
/// `MarkdownLite`'s special characters (`*`, `~`, `#`, `>`), so it survives
/// parsing as ordinary literal text inside whatever run it lands in. Each
/// exporter substitutes its own real footnote-reference markup for the
/// marker after block/run generation, rather than threading footnote data
/// through every block/run builder's signature.
class FootnoteMarkers {
  FootnoteMarkers._();

  static final _marker = String.fromCharCode(0xE000);
  static final pattern =
      RegExp('${String.fromCharCode(0xE000)}(\\d+)${String.fromCharCode(0xE000)}');

  static String wrap(int number) => '$_marker$number$_marker';

  /// Cheap pre-check before running [pattern] against a run's text — footnote
  /// markers are rare (most runs have none), so this single-char `contains`
  /// scan lets callers skip the regex machinery on the common no-marker path.
  static bool mayContainMarker(String text) => text.contains(_marker);

  /// Reads every footnote annotation for [sceneId], numbers them in document
  /// order starting at [startNumber] (continuing one sequence across the
  /// whole book, not resetting per scene), inserts a marker at each one's
  /// anchor offset into [content] — rightmost offset first, so an earlier
  /// insertion's length doesn't shift the still-unprocessed offsets before
  /// it — and returns the marked-up content plus the numbered footnote
  /// bodies and the next number to continue from for the following scene.
  static Future<FootnoteMarkResult> markContent({
    required AnnotationService annotations,
    required String sceneId,
    required String content,
    required int startNumber,
  }) async {
    final footnotes = (await annotations.listForScene(sceneId))
        .where((a) => a.kind == AnnotationKind.footnote)
        .toList()
      ..sort((a, b) => a.anchor.start.compareTo(b.anchor.start));

    var number = startNumber;
    final bodies = <int, String>{};
    final numbered = <(int number, Annotation footnote)>[];
    for (final footnote in footnotes) {
      bodies[number] = footnote.body;
      numbered.add((number, footnote));
      number++;
    }

    var marked = content;
    for (final (num, footnote) in numbered.reversed) {
      final clamped = footnote.anchor.start.clamp(0, marked.length);
      marked = marked.substring(0, clamped) + wrap(num) + marked.substring(clamped);
    }

    return FootnoteMarkResult(content: marked, bodies: bodies, nextNumber: number);
  }
}

class FootnoteMarkResult {
  const FootnoteMarkResult({
    required this.content,
    required this.bodies,
    required this.nextNumber,
  });

  final String content;
  final Map<int, String> bodies;
  final int nextNumber;
}
