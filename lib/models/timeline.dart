/// Timeline — in-story chronology, distinct from the Plot Grid (structural,
/// manuscript order) and Version History (real-world edit history). Mirrors
/// `timelines/timeline-<id>.json` (a track) and `timelines/event-<id>.json`
/// (see PLAN.md "Data model" and "Feature: Timeline Page").
library;

/// One parallel strand ("Main", "Backstory", a POV character's arc, ...).
/// Toggleable/overlayable in the Timeline screen. [order] is this track's
/// row position among the others (ascending) — user-reorderable, swapped
/// with a neighbour rather than freely dragged (see `TimelineService.moveTrack`).
class TimelineTrack {
  final String id;
  String name;
  int order;

  TimelineTrack({required this.id, required this.name, this.order = 0});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'order': order};

  factory TimelineTrack.fromJson(Map<String, dynamic> json) => TimelineTrack(
        id: json['id'] as String,
        name: json['name'] as String,
        order: json['order'] as int? ?? 0,
      );
}

/// A moment on a track. [timeLabel] is freeform ("Day 3", "Spring, Year 1",
/// an ISO date) rather than a parsed `DateTime` — in-story time is often not
/// a real calendar (flashbacks, secondary-world calendars, "three years
/// before the war"), so PLAN.md's "date or relative-time marker" is treated
/// as text the author controls.
///
/// Position is free-form rather than a simple left-to-right sequence: [x] is
/// the event's horizontal position on its track's shared canvas (time reads
/// left-to-right, but nothing snaps it to a grid column), and [yOffset] is
/// its vertical offset from the track's own baseline row — letting events
/// that are close together in time be staggered above/below the line instead
/// of overlapping. The track (a row) is still what the event belongs to;
/// only its position within that row's freeform space is unconstrained.
class TimelineEvent {
  final String id;
  final String trackId;
  String label;
  String timeLabel;
  double x;
  double yOffset;
  String notes;
  List<String> linkedSceneIds;
  List<String> linkedCharacterIds;
  List<String> linkedWorldIds;

  TimelineEvent({
    required this.id,
    required this.trackId,
    required this.label,
    this.timeLabel = '',
    this.x = 0,
    this.yOffset = 0,
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
    double? x,
    double? yOffset,
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
        x: x ?? this.x,
        yOffset: yOffset ?? this.yOffset,
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
        'x': x,
        'yOffset': yOffset,
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
        // 'order' is the pre-freeform-layout field name; reading it as a
        // fallback keeps events created before this change from all piling
        // up at x=0 the first time their project is opened.
        x: (json['x'] as num?)?.toDouble() ?? ((json['order'] as num?)?.toDouble() ?? 0) * 180,
        yOffset: (json['yOffset'] as num?)?.toDouble() ?? 0,
        notes: json['notes'] as String? ?? '',
        linkedSceneIds: (json['linkedSceneIds'] as List<dynamic>? ?? []).cast<String>(),
        linkedCharacterIds:
            (json['linkedCharacterIds'] as List<dynamic>? ?? []).cast<String>(),
        linkedWorldIds: (json['linkedWorldIds'] as List<dynamic>? ?? []).cast<String>(),
      );
}
