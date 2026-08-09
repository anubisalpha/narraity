/// A publishing-planning milestone/deadline for a project — "Query package
/// due", "Send to beta readers", "KDP launch date". Distinct from the
/// in-story [TimelineTrack]/[TimelineEvent] (story chronology, not
/// real-world planning) and from [TodoItem] (unscheduled, no due date).
/// Mirrors `planning/milestones.json`.
class PlanningMilestone {
  PlanningMilestone({
    required this.id,
    required this.title,
    this.notes = '',
    this.dueDate,
    this.done = false,
    this.reminderDaysBefore = 7,
    this.linkedContactId,
  });

  final String id;
  String title;
  String notes;
  DateTime? dueDate;
  bool done;
  int reminderDaysBefore;
  String? linkedContactId;

  /// Computed, not stored — avoids a stale "overdue" flag surviving past
  /// its due date, or a stale "done" status if the due date is edited later.
  PlanningMilestoneStatus statusAsOf(DateTime now) {
    if (done) return PlanningMilestoneStatus.done;
    final due = dueDate;
    if (due == null) return PlanningMilestoneStatus.upcoming;
    if (due.isBefore(now)) return PlanningMilestoneStatus.overdue;
    if (due.isBefore(now.add(Duration(days: reminderDaysBefore)))) {
      return PlanningMilestoneStatus.dueSoon;
    }
    return PlanningMilestoneStatus.upcoming;
  }

  PlanningMilestone copyWith({
    String? title,
    String? notes,
    DateTime? dueDate,
    bool clearDueDate = false,
    bool? done,
    int? reminderDaysBefore,
    String? linkedContactId,
    bool clearLinkedContactId = false,
  }) => PlanningMilestone(
    id: id,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
    done: done ?? this.done,
    reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
    linkedContactId: clearLinkedContactId
        ? null
        : (linkedContactId ?? this.linkedContactId),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'notes': notes,
    if (dueDate != null) 'dueDate': dueDate!.toIso8601String(),
    'done': done,
    'reminderDaysBefore': reminderDaysBefore,
    if (linkedContactId != null) 'linkedContactId': linkedContactId,
  };

  factory PlanningMilestone.fromJson(Map<String, dynamic> json) =>
      PlanningMilestone(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Untitled milestone',
        notes: json['notes'] as String? ?? '',
        dueDate: json['dueDate'] == null
            ? null
            : DateTime.parse(json['dueDate'] as String),
        done: json['done'] as bool? ?? false,
        reminderDaysBefore: json['reminderDaysBefore'] as int? ?? 7,
        linkedContactId: json['linkedContactId'] as String?,
      );
}

enum PlanningMilestoneStatus { overdue, dueSoon, upcoming, done }
