/// A captured idea living outside any single project — mirrors
/// `_GlobalIdeas/idea-<id>.json` on disk (see PLAN.md "Global Ideas").
enum IdeaStatus { active, used }

class Idea {
  final String id;
  final String title;
  final String body;
  final List<String> tags;
  final DateTime created;
  final IdeaStatus status;

  /// Set when the idea was promoted to (or attached to) a project —
  /// keeps the origin trail instead of deleting the idea.
  final String? linkedProjectId;

  const Idea({
    required this.id,
    required this.title,
    required this.body,
    required this.tags,
    required this.created,
    this.status = IdeaStatus.active,
    this.linkedProjectId,
  });

  Idea copyWith({
    String? title,
    String? body,
    List<String>? tags,
    IdeaStatus? status,
    String? linkedProjectId,
  }) {
    return Idea(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      tags: tags ?? this.tags,
      created: created,
      status: status ?? this.status,
      linkedProjectId: linkedProjectId ?? this.linkedProjectId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'tags': tags,
        'created': created.toIso8601String(),
        'status': status.name,
        if (linkedProjectId != null) 'linkedProjectId': linkedProjectId,
      };

  factory Idea.fromJson(Map<String, dynamic> json) {
    return Idea(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
      created: DateTime.parse(json['created'] as String),
      status: IdeaStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => IdeaStatus.active,
      ),
      linkedProjectId: json['linkedProjectId'] as String?,
    );
  }
}
