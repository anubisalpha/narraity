/// Purely visual — which library-card frame/icon style a project uses.
/// Doesn't affect the manuscript, editor, or export pipeline at all (a
/// "Script" project is still prose-formatted the same as a "Novel" one);
/// see PLAN.md's Feature section for why real screenplay formatting is
/// explicitly a separate, much bigger feature this isn't attempting.
enum ProjectKind { novel, comic, script }

/// A single novel-writing project (or one book inside a series, in later phases).
///
/// Mirrors `project.json` on disk — see PLAN.md's "Data model" section.
class Project {
  final String id;
  final String folderName;
  final String title;
  final String? subtitle;
  final String? author;
  final DateTime created;
  final DateTime modified;

  /// Set when this project belongs to a Series (see `models/series.dart`).
  /// Null means "standalone" — the library shows it as its own card rather
  /// than folded into a series' stacked card.
  final String? seriesId;

  /// Path to the cover image file, relative to the project's own folder
  /// (e.g. `assets/covers/cover.jpg`) — resolve against `ManuscriptService.
  /// projectDir` (or `LibraryService.libraryRoot()`/folderName) to get an
  /// absolute path. Null means no cover has been set.
  final String? coverImagePath;

  /// Which card frame/icon style this project's library card uses — purely
  /// cosmetic (see [ProjectKind]'s doc comment). Defaults to [ProjectKind.novel]
  /// for any project created or saved before this field existed.
  final ProjectKind kind;

  /// Manual library-grid position, set by drag-and-drop reordering. Null
  /// means "never manually reordered" — the library sorts those by recency
  /// instead, after every explicitly-ordered item. See `_LibraryGrid`'s sort
  /// in `library_screen.dart`.
  final int? sortOrder;

  const Project({
    required this.id,
    required this.folderName,
    required this.title,
    this.subtitle,
    this.author,
    required this.created,
    required this.modified,
    this.seriesId,
    this.coverImagePath,
    this.kind = ProjectKind.novel,
    this.sortOrder,
  });

  /// Clears [seriesId]/[coverImagePath] when their `clear*` flag is true;
  /// otherwise the corresponding value (if given) sets it, and omitting
  /// both leaves it unchanged — a plain nullable param can't distinguish
  /// "leave as-is" from "set to null".
  Project copyWith({
    String? title,
    String? subtitle,
    String? author,
    DateTime? modified,
    String? seriesId,
    bool clearSeriesId = false,
    String? coverImagePath,
    bool clearCoverImagePath = false,
    ProjectKind? kind,
    int? sortOrder,
  }) {
    return Project(
      id: id,
      folderName: folderName,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      author: author ?? this.author,
      created: created,
      modified: modified ?? this.modified,
      seriesId: clearSeriesId ? null : (seriesId ?? this.seriesId),
      coverImagePath: clearCoverImagePath
          ? null
          : (coverImagePath ?? this.coverImagePath),
      kind: kind ?? this.kind,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (subtitle != null) 'subtitle': subtitle,
    if (author != null) 'author': author,
    'created': created.toIso8601String(),
    'modified': modified.toIso8601String(),
    if (seriesId != null) 'seriesId': seriesId,
    if (coverImagePath != null) 'coverImagePath': coverImagePath,
    'kind': kind.name,
    if (sortOrder != null) 'sortOrder': sortOrder,
  };

  factory Project.fromJson(
    Map<String, dynamic> json, {
    required String folderName,
  }) {
    return Project(
      id: json['id'] as String,
      folderName: folderName,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      author: json['author'] as String?,
      created: DateTime.parse(json['created'] as String),
      modified: DateTime.parse(json['modified'] as String),
      seriesId: json['seriesId'] as String?,
      coverImagePath: json['coverImagePath'] as String?,
      kind: ProjectKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => ProjectKind.novel,
      ),
      sortOrder: json['sortOrder'] as int?,
    );
  }
}
