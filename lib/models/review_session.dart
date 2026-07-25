import '../services/review_markdown_parser.dart';

/// A saved reviewer session — the record of one pass through an exported
/// review Markdown file, kept as its own persistent section (mirrors
/// `_GlobalIdeas/`'s "works without any project open" pattern) so a
/// reviewer's comments survive between sittings rather than being lost the
/// moment they close the export screen.
class ReviewSession {
  ReviewSession({
    required this.id,
    required this.title,
    required this.paragraphs,
    this.metadata,
    Map<String, ReviewComment>? comments,
    required this.created,
    DateTime? modified,
  }) : comments = comments ?? {},
       modified = modified ?? created;

  final String id;
  String title;
  final List<ReviewParagraph> paragraphs;

  /// Project title/subtitle/author/export-timestamp read out of the export
  /// file's metadata comment, if it had one — null for files exported before
  /// this existed, or a hand-edited file with no such comment.
  final ReviewExportMetadata? metadata;

  /// Keyed by anchor id — one comment per paragraph, same "overwrite rather
  /// than stack a second one nobody can see" precedent as Plot Grid's
  /// `setPlotPoint`.
  final Map<String, ReviewComment> comments;
  final DateTime created;
  DateTime modified;

  int get commentCount => comments.length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'paragraphs': paragraphs.map((p) => p.toJson()).toList(),
    if (metadata != null) 'metadata': metadata!.toJson(),
    'comments': comments.map((id, c) => MapEntry(id, c.toJson())),
    'created': created.toIso8601String(),
    'modified': modified.toIso8601String(),
  };

  factory ReviewSession.fromJson(Map<String, dynamic> json) {
    final created = DateTime.parse(json['created'] as String);
    return ReviewSession(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled review',
      paragraphs: (json['paragraphs'] as List<dynamic>? ?? [])
          .map((p) => ReviewParagraph.fromJson(p as Map<String, dynamic>))
          .toList(),
      metadata: json['metadata'] == null
          ? null
          : ReviewExportMetadata.fromJson(
              json['metadata'] as Map<String, dynamic>,
            ),
      comments: (json['comments'] as Map<String, dynamic>? ?? {}).map(
        (id, c) =>
            MapEntry(id, ReviewComment.fromJson(c as Map<String, dynamic>)),
      ),
      created: created,
      modified: json['modified'] == null
          ? created
          : DateTime.parse(json['modified'] as String),
    );
  }
}
