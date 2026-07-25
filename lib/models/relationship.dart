/// Family tree / relationship diagram — nodes are characters (pulled from
/// existing Character Profiles), edges are relationships. Mirrors
/// `relationships/relationship-<id>.json` (see PLAN.md "Data model" and
/// "Feature: Family Tree / Relationship Diagram"), with one deliberate
/// deviation: PLAN.md puts `position` on the relationship record, but
/// position is a property of a *node* (a character), not an *edge* — a
/// character with two relationships (or none yet) can only have one canvas
/// position, so it's stored separately in `relationships/layout.json` keyed
/// by character id instead.
library;

enum RelationshipType { family, romantic, friend, rival, ally, mentor, other }

extension RelationshipTypeLabel on RelationshipType {
  String get label => switch (this) {
        RelationshipType.family => 'Family',
        RelationshipType.romantic => 'Romantic',
        RelationshipType.friend => 'Friend',
        RelationshipType.rival => 'Rival',
        RelationshipType.ally => 'Ally',
        RelationshipType.mentor => 'Mentor',
        RelationshipType.other => 'Other',
      };
}

class Relationship {
  final String id;
  final String characterAId;
  final String characterBId;
  RelationshipType type;

  /// Optional detail beyond the type ("estranged", "secretly in love with"),
  /// shown alongside the type label on the edge.
  String label;

  Relationship({
    required this.id,
    required this.characterAId,
    required this.characterBId,
    required this.type,
    this.label = '',
  });

  Relationship copyWith({RelationshipType? type, String? label}) => Relationship(
        id: id,
        characterAId: characterAId,
        characterBId: characterBId,
        type: type ?? this.type,
        label: label ?? this.label,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'characterAId': characterAId,
        'characterBId': characterBId,
        'type': type.name,
        'label': label,
      };

  factory Relationship.fromJson(Map<String, dynamic> json) => Relationship(
        id: json['id'] as String,
        characterAId: json['characterAId'] as String,
        characterBId: json['characterBId'] as String,
        type: RelationshipType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => RelationshipType.other,
        ),
        label: json['label'] as String? ?? '',
      );
}
