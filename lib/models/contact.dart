/// A real-world person or organisation involved in getting a manuscript
/// published — an agent, editor, beta reader, ARC reviewer, cover designer,
/// or publisher. Library-root scope (not tied to one project) since a
/// contact — especially an agent — may be relevant across several
/// manuscripts. Mirrors `_Contacts/contact-<id>.json`.
enum ContactRole {
  agent,
  editor,
  betaReader,
  arcReviewer,
  publisher,
  coverDesigner,
  other,
}

extension ContactRoleLabel on ContactRole {
  String get label => switch (this) {
    ContactRole.agent => 'Agent',
    ContactRole.editor => 'Editor',
    ContactRole.betaReader => 'Beta Reader',
    ContactRole.arcReviewer => 'ARC Reviewer',
    ContactRole.publisher => 'Publisher',
    ContactRole.coverDesigner => 'Cover Designer',
    ContactRole.other => 'Other',
  };
}

class Contact {
  Contact({
    required this.id,
    required this.name,
    required this.role,
    this.email = '',
    this.notes = '',
    required this.created,
    DateTime? modified,
  }) : modified = modified ?? created;

  final String id;
  String name;
  ContactRole role;
  String email;
  String notes;
  final DateTime created;
  DateTime modified;

  Contact copyWith({
    String? name,
    ContactRole? role,
    String? email,
    String? notes,
  }) => Contact(
    id: id,
    name: name ?? this.name,
    role: role ?? this.role,
    email: email ?? this.email,
    notes: notes ?? this.notes,
    created: created,
    modified: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role.name,
    'email': email,
    'notes': notes,
    'created': created.toIso8601String(),
    'modified': modified.toIso8601String(),
  };

  factory Contact.fromJson(Map<String, dynamic> json) {
    final created = DateTime.parse(json['created'] as String);
    return Contact(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Unnamed contact',
      role: ContactRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => ContactRole.other,
      ),
      email: json['email'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      created: created,
      modified: json['modified'] == null
          ? created
          : DateTime.parse(json['modified'] as String),
    );
  }
}
