/// A character profile or worldbuilding entry — mirrors
/// `characters/char-<id>.json` and `worldbuilding/entry-<id>.json` on disk
/// (see PLAN.md "Data model").
///
/// Characters and world entries share one model because they differ only in
/// where they're stored and which starter fields they seed with — both are
/// "a named thing with author-defined fields, some of which are worth showing
/// at a glance." Splitting them into two near-identical classes would mean
/// two of everything downstream (services, editors, Reference Panel cards)
/// for no behavioural difference.
///
/// [fields] is deliberately an ordered map of author-chosen names to values
/// rather than fixed properties: every writer wants different things on a
/// character sheet, and a fixed schema would be wrong for most of them.
/// `jsonDecode` preserves insertion order, and every write rewrites the whole
/// object, so the author's field order survives round-trips.
enum ProfileKind { character, world }

class ProfileEntry {
  final String id;
  final String name;

  /// Project-relative path to the attached image (e.g.
  /// `assets/images/<id>.png`), or null. Stored relative so moving or
  /// restoring a project folder doesn't break the reference.
  final String? imagePath;

  /// Freeform grouping for world entries ("Location", "Faction", …); always
  /// null for characters, which aren't grouped.
  final String? category;

  /// Names of the [fields] the author flagged as "show at a glance". Consumed
  /// by the Reference Panel (Phase 2.5) to render compact cards instead of
  /// the full profile.
  final List<String> quickRef;

  final Map<String, String> fields;
  final DateTime created;
  final DateTime modified;

  const ProfileEntry({
    required this.id,
    required this.name,
    this.imagePath,
    this.category,
    this.quickRef = const [],
    this.fields = const {},
    required this.created,
    required this.modified,
  });

  /// Starter fields for a new entry of [kind] — a prompt, not a schema: every
  /// one can be renamed or removed, and more can be added.
  static Map<String, String> starterFields(ProfileKind kind) => switch (kind) {
        ProfileKind.character => {
            'Role': '',
            'Age': '',
            'Appearance': '',
            'Personality': '',
            'Goals': '',
            'Backstory': '',
            'Notes': '',
          },
        ProfileKind.world => {'Description': ''},
      };

  /// [clearImage]/[clearCategory] exist because passing null to the matching
  /// parameter can't be told apart from omitting it.
  ProfileEntry copyWith({
    String? name,
    String? imagePath,
    bool clearImage = false,
    String? category,
    bool clearCategory = false,
    List<String>? quickRef,
    Map<String, String>? fields,
    DateTime? modified,
  }) {
    return ProfileEntry(
      id: id,
      name: name ?? this.name,
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      category: clearCategory ? null : (category ?? this.category),
      quickRef: quickRef ?? this.quickRef,
      fields: fields ?? this.fields,
      created: created,
      modified: modified ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (imagePath != null) 'imagePath': imagePath,
        if (category != null) 'category': category,
        'quickRef': quickRef,
        'fields': fields,
        'created': created.toIso8601String(),
        'modified': modified.toIso8601String(),
      };

  factory ProfileEntry.fromJson(Map<String, dynamic> json) {
    final created = DateTime.parse(json['created'] as String);
    return ProfileEntry(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled',
      imagePath: json['imagePath'] as String?,
      category: json['category'] as String?,
      quickRef: (json['quickRef'] as List<dynamic>? ?? []).cast<String>(),
      fields: (json['fields'] as Map<String, dynamic>? ?? {})
          .map((key, value) => MapEntry(key, value?.toString() ?? '')),
      created: created,
      modified: json['modified'] == null
          ? created
          : DateTime.parse(json['modified'] as String),
    );
  }
}
