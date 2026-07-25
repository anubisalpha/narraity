/// Timeline — in-story chronology, distinct from the Plot Grid (structural,
/// manuscript order) and Version History (real-world edit history). Mirrors
/// `timelines/timeline-<id>.json` (a track) and `timelines/event-<id>.json`
/// (see PLAN.md "Data model" and "Feature: Timeline Page").
library;

/// One parallel strand ("Main", "Backstory", a POV character's arc, ...).
/// Toggleable/overlayable in the Timeline screen.
class TimelineTrack {
  final String id;
  String name;

  TimelineTrack({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory TimelineTrack.fromJson(Map<String, dynamic> json) =>
      TimelineTrack(id: json['id'] as String, name: json['name'] as String);
}

/// A moment on a track. [timeLabel] is freeform ("Day 3", "Spring, Year 1",
/// an ISO date) rather than a parsed `DateTime` — in-story time is often not
/// a real calendar (flashbacks, secondary-world calendars, "three years
/// before the war"), so PLAN.md's "date or relative-time marker" is treated
/// as text the author controls. [order] is this event's position among its
/// track's other events (ascending); there's no continuous timeline axis to
/// place it on, just "before/after its trackmates".
class TimelineEvent {
  final String id;
  final String trackId;
  String label;
  String timeLabel;
  int order;
  String notes;
  List<String> linkedSceneIds;
  List<String> linkedCharacterIds;
  List<String> linkedWorldIds;

  TimelineEvent({
    required this.id,
    required this.trackId,
    required this.label,
    this.timeLabel = '',
    this.order = 0,
    this.notes = '',
    List<String>? linkedSceneIds,
    List<String>? linkedCharacterIds,
    List<String>? linkedWorldIds,
  })  : linkedSceneIds = linkedSceneIds ?? [],
        linkedCharacterIds = linkedCharacterIds ?? [],
        linkedWorldIds = linkedWorldIds ?? [];

  TimelineEvent copyWith({
    String? label,
    String? timeLabel,
    int? order,
    String? notes,
    List<String>? linkedSceneIds,
    List<String>? linkedCharacterIds,
    List<String>? linkedWorldIds,
  }) =>
      TimelineEvent(
        id: id,
        trackId: trackId,
        label: label ?? this.label,
        timeLabel: timeLabel ?? this.timeLabel,
        order: order ?? this.order,
        notes: notes ?? this.notes,
        linkedSceneIds: linkedSceneIds ?? this.linkedSceneIds,
        linkedCharacterIds: linkedCharacterIds ?? this.linkedCharacterIds,
        linkedWorldIds: linkedWorldIds ?? this.linkedWorldIds,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'trackId': trackId,
        'label': label,
        'timeLabel': timeLabel,
        'order': order,
        'notes': notes,
        'linkedSceneIds': linkedSceneIds,
        'linkedCharacterIds': linkedCharacterIds,
        'linkedWorldIds': linkedWorldIds,
      };

  factory TimelineEvent.fromJson(Map<String, dynamic> json) => TimelineEvent(
        id: json['id'] as String,
        trackId: json['trackId'] as String,
        label: json['label'] as String,
        timeLabel: json['timeLabel'] as String? ?? '',
        order: json['order'] as int? ?? 0,
        notes: json['notes'] as String? ?? '',
        linkedSceneIds: (json['linkedSceneIds'] as List<dynamic>? ?? []).cast<String>(),
        linkedCharacterIds:
            (json['linkedCharacterIds'] as List<dynamic>? ?? []).cast<String>(),
        linkedWorldIds: (json['linkedWorldIds'] as List<dynamic>? ?? []).cast<String>(),
      );
}
