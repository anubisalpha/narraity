/// A story note — mirrors `notes/note-<id>.json`, or
/// `notes/<Folder>/note-<id>.json` once filed into a folder.
///
/// [folder] is *not* persisted in the JSON: it's derived from where the file
/// actually sits, so moving a note between folders is a plain file move and
/// the folder structure stays true even if someone rearranges the files
/// outside the app (which local-first storage invites).
class StoryNote {
  final String id;
  final String title;
  final String body;
  final List<String> tags;

  /// Containing folder name, or null for a note at the notes root. Derived
  /// from the file's location — see [StoryNotesService].
  final String? folder;

  /// Set to `globalIdea` on notes seeded by promoting a Global Idea, so the
  /// origin trail survives (see IdeasService.promoteToNewProject).
  final String? source;

  final DateTime created;
  final DateTime modified;

  const StoryNote({
    required this.id,
    required this.title,
    required this.body,
    this.tags = const [],
    this.folder,
    this.source,
    required this.created,
    required this.modified,
  });

  StoryNote copyWith({
    String? title,
    String? body,
    List<String>? tags,
    String? folder,
    bool clearFolder = false,
    DateTime? modified,
  }) {
    return StoryNote(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      tags: tags ?? this.tags,
      folder: clearFolder ? null : (folder ?? this.folder),
      source: source,
      created: created,
      modified: modified ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'tags': tags,
        if (source != null) 'source': source,
        'created': created.toIso8601String(),
        'modified': modified.toIso8601String(),
      };

  /// Also reads the shape written by `IdeasService._seedNote` for promoted
  /// Global Ideas, which predates this model: no `modified` field, and an id
  /// that already carries the `note-` prefix. Those notes are real notes and
  /// must appear in the panel, so tolerating their shape matters more than
  /// insisting on one canonical format.
  factory StoryNote.fromJson(Map<String, dynamic> json, {String? folder}) {
    final created = DateTime.parse(json['created'] as String);
    return StoryNote(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled',
      body: json['body'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
      folder: folder,
      source: json['source'] as String?,
      created: created,
      modified: json['modified'] == null
          ? created
          : DateTime.parse(json['modified'] as String),
    );
  }
}
