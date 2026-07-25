/// Phase 4's shared text-anchoring mechanism: comments, highlights, sticky
/// notes, and footnotes are all "a note attached to a range of scene text",
/// differing only in what the note *is* (matches the Phase 2 "one model,
/// kind enum" precedent from `ProfileEntry`/`ProfileKind`). Mirrors
/// `annotations/annotations.json` — deliberately a new top-level folder, not
/// PLAN.md's literal `notes/note-<id>.json`, because `notes/` is already
/// Story Notes' folder-and-tag-organized free notes (Phase 2) — a different
/// concept that happens to share a name in the original plan.
library;

enum AnnotationKind { comment, highlight, stickyNote, footnote }

/// How a [TextAnchor] resolved against a scene's *current* content, which
/// may have been edited since the anchor was created.
enum AnchorStatus {
  /// Recorded offsets still hold the exact quoted text — nothing to do.
  exact,

  /// The quoted text still exists verbatim, just at a different offset
  /// (something earlier in the document changed length). Resolved
  /// offsets point at the real match; safe to persist silently.
  moved,

  /// The quoted text no longer appears anywhere in the content (edited or
  /// deleted). Resolved offsets are a best-effort clamp of the *original*
  /// position, not a real match — callers should flag this to the user
  /// ("approximate placement — verify") rather than silently trusting it.
  orphaned,
}

class AnchorResolution {
  const AnchorResolution({required this.status, required this.start, required this.end});

  final AnchorStatus status;
  final int start;
  final int end;
}

/// Anchors an annotation to a `[start, end)` character range in a scene's
/// plain-text/markdown `content` string. `start == end` is a valid
/// zero-length anchor (footnotes mark a point, not a span).
class TextAnchor {
  const TextAnchor({required this.start, required this.end, required this.quotedText});

  final int start;
  final int end;

  /// Snapshot of `content.substring(start, end)` at creation/last-resolve
  /// time — the only way to tell "text moved" from "text changed" once
  /// offsets alone no longer line up.
  final String quotedText;

  Map<String, dynamic> toJson() => {'start': start, 'end': end, 'quotedText': quotedText};

  factory TextAnchor.fromJson(Map<String, dynamic> json) => TextAnchor(
        start: json['start'] as int,
        end: json['end'] as int,
        quotedText: json['quotedText'] as String? ?? '',
      );

  /// Re-locates this anchor against the scene's current [content].
  ///
  /// Point anchors (`quotedText` empty) can't be searched for, so they're
  /// just clamped into range and reported `exact` — there's no "moved" vs
  /// "orphaned" distinction for a marker with no text of its own.
  AnchorResolution resolveIn(String content) {
    if (quotedText.isEmpty) {
      final clamped = start.clamp(0, content.length);
      return AnchorResolution(status: AnchorStatus.exact, start: clamped, end: clamped);
    }

    final inBounds = start >= 0 && end <= content.length && start <= end;
    if (inBounds && content.substring(start, end) == quotedText) {
      return AnchorResolution(status: AnchorStatus.exact, start: start, end: end);
    }

    // Text still exists somewhere — find the occurrence closest to the
    // originally recorded start, since a doc can repeat a phrase.
    final matchStarts = <int>[];
    var searchFrom = 0;
    while (true) {
      final found = content.indexOf(quotedText, searchFrom);
      if (found == -1) break;
      matchStarts.add(found);
      searchFrom = found + 1;
    }

    if (matchStarts.isEmpty) {
      final clampedStart = start.clamp(0, content.length);
      final clampedEnd = end.clamp(clampedStart, content.length);
      return AnchorResolution(
          status: AnchorStatus.orphaned, start: clampedStart, end: clampedEnd);
    }

    matchStarts.sort((a, b) => (a - start).abs().compareTo((b - start).abs()));
    final nearest = matchStarts.first;
    return AnchorResolution(
        status: AnchorStatus.moved, start: nearest, end: nearest + quotedText.length);
  }
}

/// One comment, highlight, sticky note, or footnote attached to a scene.
///
/// [body] holds the note text (comment body, sticky note body, footnote
/// text) — empty and unused for a plain highlight. [color] is an ARGB int
/// (highlight only), following [PlotLine]'s "store colour as a plain int so
/// the model stays Flutter-free" precedent. [resolved] is a comment-thread
/// "done" flag; harmless and unused on the other three kinds.
class Annotation {
  Annotation({
    required this.id,
    required this.sceneId,
    required this.kind,
    required this.anchor,
    this.body = '',
    this.color,
    this.resolved = false,
    required this.created,
    required this.modified,
  });

  final String id;
  final String sceneId;
  final AnnotationKind kind;
  TextAnchor anchor;
  String body;
  int? color;
  bool resolved;
  final DateTime created;
  DateTime modified;

  Annotation copyWith({
    TextAnchor? anchor,
    String? body,
    int? color,
    bool? resolved,
    DateTime? modified,
  }) =>
      Annotation(
        id: id,
        sceneId: sceneId,
        kind: kind,
        anchor: anchor ?? this.anchor,
        body: body ?? this.body,
        color: color ?? this.color,
        resolved: resolved ?? this.resolved,
        created: created,
        modified: modified ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sceneId': sceneId,
        'kind': kind.name,
        'anchor': anchor.toJson(),
        'body': body,
        if (color != null) 'color': color,
        'resolved': resolved,
        'created': created.toIso8601String(),
        'modified': modified.toIso8601String(),
      };

  factory Annotation.fromJson(Map<String, dynamic> json) => Annotation(
        id: json['id'] as String,
        sceneId: json['sceneId'] as String,
        kind: AnnotationKind.values.byName(json['kind'] as String),
        anchor: TextAnchor.fromJson(json['anchor'] as Map<String, dynamic>),
        body: json['body'] as String? ?? '',
        color: json['color'] as int?,
        resolved: json['resolved'] as bool? ?? false,
        created: DateTime.parse(json['created'] as String),
        modified: DateTime.parse(json['modified'] as String),
      );
}
