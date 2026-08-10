/// A named grouping of projects — mirrors `_Series/series-<id>.json` on
/// disk, alongside (not inside) project folders, same reserved-folder
/// convention as `_GlobalIdeas/` and `_ReviewSessions/`. A series holds no
/// manuscript content of its own; membership lives on each `Project.seriesId`.
class Series {
  final String id;
  final String title;
  final DateTime created;
  final DateTime modified;

  /// Manual library-grid position, set by drag-and-drop reordering —
  /// mirrors `Project.sortOrder`; see that field's doc for the sort rule.
  final int? sortOrder;

  /// Path to the series' own cover image file, relative to the library root
  /// (e.g. `_Series/covers/series-<id>.jpg`) — resolve against
  /// `LibraryService.libraryRoot()` to get an absolute path. Null means no
  /// dedicated series cover has been set, in which case the library card
  /// falls back to showing member projects' own covers instead (see
  /// `_SeriesStackCard` in `library_screen.dart`).
  final String? coverImagePath;

  const Series({
    required this.id,
    required this.title,
    required this.created,
    required this.modified,
    this.sortOrder,
    this.coverImagePath,
  });

  /// Clears [coverImagePath] when [clearCoverImagePath] is true; otherwise a
  /// given [coverImagePath] sets it, and omitting both leaves it unchanged —
  /// same reasoning as `Project.copyWith`'s matching flag.
  Series copyWith({
    String? title,
    DateTime? modified,
    int? sortOrder,
    String? coverImagePath,
    bool clearCoverImagePath = false,
  }) =>
      Series(
        id: id,
        title: title ?? this.title,
        created: created,
        modified: modified ?? this.modified,
        sortOrder: sortOrder ?? this.sortOrder,
        coverImagePath: clearCoverImagePath
            ? null
            : (coverImagePath ?? this.coverImagePath),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'created': created.toIso8601String(),
        'modified': modified.toIso8601String(),
        if (sortOrder != null) 'sortOrder': sortOrder,
        if (coverImagePath != null) 'coverImagePath': coverImagePath,
      };

  factory Series.fromJson(Map<String, dynamic> json) => Series(
        id: json['id'] as String,
        title: json['title'] as String,
        created: DateTime.parse(json['created'] as String),
        modified: DateTime.parse(json['modified'] as String),
        sortOrder: json['sortOrder'] as int?,
        coverImagePath: json['coverImagePath'] as String?,
      );

  /// Equality by [id] alone — see [Project]'s matching override for why:
  /// every other field can be edited via [copyWith], and without this,
  /// family providers keyed by a whole `Series` would treat every edited
  /// copy (a rename, a reorder) as a brand-new provider instance.
  @override
  bool operator ==(Object other) => other is Series && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
