import 'package:flutter/material.dart';

import '../models/annotation.dart';

/// A [TextEditingController] that paints Phase 4 annotation ranges
/// (highlight/comment/sticky-note spans) as background tints directly in the
/// plain-text scene editor, without needing a rich-text delta model. Also
/// paints two transient overlays that are never persisted and change too
/// often to model as `Annotation`s: a "currently speaking" range for Read
/// Aloud (one range, changes on every word boundary), and misspelled-word
/// ranges for spell check (Phase 4.5, many ranges, recomputed on a debounce
/// after edits).
///
/// Footnote anchors are zero-length points (`start == end`) and have nothing
/// to paint here — they only show up in the annotations panel until a
/// rich-text editor can render an inline superscript marker.
///
/// While any annotation or overlay is present, this bypasses the default
/// `buildTextSpan`'s IME composing-region styling (acceptable trade-off: a
/// plain-text editor with none of them still gets normal composing behavior
/// via the `super` fallback below).
class AnnotationHighlightController extends TextEditingController {
  AnnotationHighlightController({super.text});

  List<(Annotation, AnchorResolution)> _resolved = const [];
  (int start, int end)? _speakingRange;
  List<(int start, int end)> _misspelledRanges = const [];

  set annotations(List<(Annotation, AnchorResolution)> resolved) {
    _resolved = resolved;
    notifyListeners();
  }

  List<(Annotation, AnchorResolution)> get annotations => _resolved;

  /// Set to the word currently being read aloud (character range in this
  /// controller's own text), or null when not speaking.
  set speakingRange((int start, int end)? range) {
    _speakingRange = range;
    notifyListeners();
  }

  /// Character ranges of every word spell check flagged in the current
  /// text. Recomputed by the editor on a debounce, not on every keystroke.
  set misspelledRanges(List<(int start, int end)> ranges) {
    _misspelledRanges = ranges;
    notifyListeners();
  }

  static const _speakingStyle = TextStyle(backgroundColor: Color(0xFFFFB74D));
  static const _misspelledStyle = TextStyle(
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.wavy,
    decorationColor: Colors.red,
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final ranges = _resolved.where((entry) => entry.$2.end > entry.$2.start).toList()
      ..sort((a, b) => a.$2.start.compareTo(b.$2.start));

    if (ranges.isEmpty && _speakingRange == null && _misspelledRanges.isEmpty) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }

    final text = value.text;
    var children = <TextSpan>[];
    var cursor = 0;

    for (final (annotation, resolution) in ranges) {
      final start = resolution.start.clamp(0, text.length);
      final end = resolution.end.clamp(start, text.length);
      if (start < cursor) continue; // overlapping ranges: first (by start) wins
      if (start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, start), style: style));
      }
      children.add(TextSpan(
        text: text.substring(start, end),
        style: (style ?? const TextStyle()).merge(_styleFor(annotation, resolution)),
      ));
      cursor = end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor), style: style));
    }

    for (final (start, end) in _misspelledRanges) {
      children = _overlayRange(
        children,
        style,
        start.clamp(0, text.length),
        end.clamp(0, text.length),
        _misspelledStyle,
      );
    }

    final speaking = _speakingRange;
    if (speaking != null) {
      children = _overlayRange(
        children,
        style,
        speaking.$1.clamp(0, text.length),
        speaking.$2.clamp(0, text.length),
        _speakingStyle,
      );
    }

    return TextSpan(style: style, children: children);
  }

  /// Splits whichever child spans overlap `[start, end)` and merges
  /// [overlayStyle] onto just the overlapping portion — a genuine overlay
  /// independent of whatever styling (if any) already applies to that
  /// stretch of text, rather than a second competing "first wins" range.
  /// Used for both the speaking range and each misspelled-word range in
  /// turn, so multiple overlays (e.g. reading through a misspelled word)
  /// compose correctly.
  List<TextSpan> _overlayRange(
    List<TextSpan> children,
    TextStyle? baseStyle,
    int start,
    int end,
    TextStyle overlayStyle,
  ) {
    if (start >= end) return children;
    final result = <TextSpan>[];
    var offset = 0;

    for (final child in children) {
      final text = child.text ?? '';
      final childStart = offset;
      final childEnd = offset + text.length;
      offset = childEnd;

      final overlapStart = start.clamp(childStart, childEnd);
      final overlapEnd = end.clamp(childStart, childEnd);
      if (overlapStart >= overlapEnd) {
        result.add(child);
        continue;
      }

      if (overlapStart > childStart) {
        result.add(TextSpan(text: text.substring(0, overlapStart - childStart), style: child.style));
      }
      result.add(TextSpan(
        text: text.substring(overlapStart - childStart, overlapEnd - childStart),
        style: (child.style ?? baseStyle ?? const TextStyle()).merge(overlayStyle),
      ));
      if (overlapEnd < childEnd) {
        result.add(TextSpan(text: text.substring(overlapEnd - childStart), style: child.style));
      }
    }
    return result;
  }

  TextStyle _styleFor(Annotation annotation, AnchorResolution resolution) {
    // Orphaned = the quoted text was recovered only by a best-effort clamp,
    // not a real match — flag it visually rather than pretend it's placed
    // correctly.
    final flagged = resolution.status == AnchorStatus.orphaned;
    final wavyRed = flagged
        ? const TextStyle(
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.wavy,
            decorationColor: Colors.red,
          )
        : const TextStyle();

    return switch (annotation.kind) {
      AnnotationKind.highlight =>
        TextStyle(backgroundColor: Color(annotation.color ?? 0xFFFFF59D)).merge(wavyRed),
      AnnotationKind.comment => const TextStyle(
            backgroundColor: Color(0x2642A5F5),
            decoration: TextDecoration.underline,
            decorationColor: Colors.blueAccent,
          )
          .merge(wavyRed),
      AnnotationKind.stickyNote => const TextStyle(backgroundColor: Color(0x40FFC107))
          .merge(wavyRed),
      AnnotationKind.footnote => const TextStyle(),
    };
  }
}
