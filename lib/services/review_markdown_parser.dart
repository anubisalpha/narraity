/// Parsing/encoding for the *reviewer's* side of the AI/external review
/// round-trip (Phase 4) — the counterpart to `ReviewExportService`, which
/// handles the *author's* side. Pure/no Flutter dependency, same
/// "keep parsing unit-testable" precedent as `paragraph_splitter.dart` and
/// `mention_scanner.dart`.
library;

import 'dart:convert';

/// One anchored paragraph read back out of an exported review Markdown file.
class ReviewParagraph {
  const ReviewParagraph({
    required this.anchorId,
    required this.sceneTitle,
    required this.text,
  });

  final String anchorId;
  final String sceneTitle;
  final String text;

  Map<String, dynamic> toJson() => {
    'anchorId': anchorId,
    'sceneTitle': sceneTitle,
    'text': text,
  };

  factory ReviewParagraph.fromJson(Map<String, dynamic> json) =>
      ReviewParagraph(
        anchorId: json['anchorId'] as String,
        sceneTitle: json['sceneTitle'] as String? ?? '',
        text: json['text'] as String,
      );
}

/// Who/what an export was for — project title, author, when it was
/// exported. Written as a single-line hidden HTML comment (a JSON blob, not
/// hand-parsed key/value lines) at the top of the file, alongside a
/// human-readable `# Title` block for anyone opening the raw `.md` outside
/// the app. Neither is mistaken for a scene heading or paragraph by
/// [parseReviewMarkdown]: the heading pattern only matches `##`, and nothing
/// before the first `<!-- id: ... -->` marker is collected as a paragraph.
class ReviewExportMetadata {
  const ReviewExportMetadata({
    required this.projectTitle,
    this.subtitle,
    this.author,
    required this.exportedAt,
  });

  final String projectTitle;
  final String? subtitle;
  final String? author;
  final DateTime exportedAt;

  Map<String, dynamic> toJson() => {
    'projectTitle': projectTitle,
    if (subtitle != null && subtitle!.trim().isNotEmpty) 'subtitle': subtitle,
    if (author != null && author!.trim().isNotEmpty) 'author': author,
    'exportedAt': exportedAt.toIso8601String(),
  };

  factory ReviewExportMetadata.fromJson(Map<String, dynamic> json) =>
      ReviewExportMetadata(
        projectTitle: json['projectTitle'] as String,
        subtitle: json['subtitle'] as String?,
        author: json['author'] as String?,
        exportedAt: DateTime.parse(json['exportedAt'] as String),
      );
}

final _metadataPattern = RegExp(
  r'^<!--\s*narraity-review-export\s+(.+?)\s*-->$',
);

/// Reads the metadata comment back out, or null if this file predates it (or
/// was hand-edited without one) — the round-trip still works either way,
/// just without the extra context.
ReviewExportMetadata? parseReviewMetadata(String markdown) {
  for (final rawLine in markdown.split('\n')) {
    final match = _metadataPattern.firstMatch(rawLine.trim());
    if (match == null) continue;
    try {
      return ReviewExportMetadata.fromJson(
        jsonDecode(match.group(1)!) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
  return null;
}

final _headingPattern = RegExp(r'^##\s+(.*)$');
final _idPattern = RegExp(r'^<!--\s*id:\s*(\S+)\s*-->$');

/// Parses the Markdown `ReviewExportService.buildExportMarkdown` produces:
/// a `## Title` heading per scene, followed by `<!-- id: ... -->` markers
/// each immediately preceding the paragraph they anchor.
List<ReviewParagraph> parseReviewMarkdown(String markdown) {
  final paragraphs = <ReviewParagraph>[];
  var currentTitle = '';
  String? pendingId;
  final buffer = StringBuffer();

  void flush() {
    final text = buffer.toString().trim();
    if (pendingId != null && text.isNotEmpty) {
      paragraphs.add(
        ReviewParagraph(
          anchorId: pendingId!,
          sceneTitle: currentTitle,
          text: text,
        ),
      );
    }
    pendingId = null;
    buffer.clear();
  }

  for (final rawLine in markdown.split('\n')) {
    final line = rawLine.trimRight();

    final heading = _headingPattern.firstMatch(line);
    if (heading != null) {
      flush();
      currentTitle = heading.group(1)!.trim();
      continue;
    }

    final id = _idPattern.firstMatch(line.trim());
    if (id != null) {
      flush();
      pendingId = id.group(1);
      continue;
    }

    if (pendingId == null) continue;
    if (line.trim().isEmpty) {
      flush();
    } else {
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(line);
    }
  }
  flush();

  return paragraphs;
}

/// One comment a reviewer has written against a paragraph, ready to encode
/// into the JSON `ReviewExportService.importComments` expects.
class ReviewComment {
  const ReviewComment({
    required this.anchorId,
    required this.text,
    this.category,
  });

  final String anchorId;
  final String text;
  final String? category;

  Map<String, dynamic> toJson() => {
    'anchorId': anchorId,
    'text': text,
    if (category != null && category!.trim().isNotEmpty) 'category': category,
  };

  factory ReviewComment.fromJson(Map<String, dynamic> json) => ReviewComment(
    anchorId: json['anchorId'] as String,
    text: json['text'] as String? ?? '',
    category: json['category'] as String?,
  );
}

String encodeReviewComments(List<ReviewComment> comments) =>
    const JsonEncoder.withIndent(
      '  ',
    ).convert({'comments': comments.map((c) => c.toJson()).toList()});
