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

  const Project({
    required this.id,
    required this.folderName,
    required this.title,
    this.subtitle,
    this.author,
    required this.created,
    required this.modified,
  });

  Project copyWith({
    String? title,
    String? subtitle,
    String? author,
    DateTime? modified,
  }) {
    return Project(
      id: id,
      folderName: folderName,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      author: author ?? this.author,
      created: created,
      modified: modified ?? this.modified,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        if (author != null) 'author': author,
        'created': created.toIso8601String(),
        'modified': modified.toIso8601String(),
      };

  factory Project.fromJson(Map<String, dynamic> json, {required String folderName}) {
    return Project(
      id: json['id'] as String,
      folderName: folderName,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      author: json['author'] as String?,
      created: DateTime.parse(json['created'] as String),
      modified: DateTime.parse(json['modified'] as String),
    );
  }
}
