/// What a goal tracks progress against. [global] goals live outside any
/// single project (library-level, e.g. "1,000,000 words this year across
/// everything") and use [Goal.projectIds] to optionally restrict which
/// projects count toward it — null/empty means every project. [project]
/// goals track one project as a whole. (Act/scene-level goal scoping was
/// dropped: the manuscript structure is now a freeform, arbitrary-depth
/// tree — see manuscript.dart — so "act" no longer names a consistent
/// concept across projects; whole-project and app-wide are the two scopes
/// that still make sense everywhere.)
enum GoalScope { project, global }

/// Which field the setup wizard leads with — the underlying math (below) is
/// identical either way, since a daily pace fundamentally needs both a word
/// target and a deadline to compute from. This just changes which one feels
/// like "the point" to the user: "I want to hit 80,000 words" vs "I want to
/// finish by March 1st" (PLAN.md: "either a fixed word count or a deadline").
enum GoalTargetType { wordCount, deadline }

/// Recurring days off (by weekday) plus one-off exceptions (holidays, busy
/// days) — PLAN.md "Working calendar". Weekdays use `DateTime.weekday`
/// (1 = Monday .. 7 = Sunday).
class WorkingCalendar {
  final Set<int> recurringDaysOff;
  final Set<DateTime> exceptionDaysOff;

  const WorkingCalendar({
    this.recurringDaysOff = const {},
    this.exceptionDaysOff = const {},
  });

  bool isWorkingDay(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);
    if (recurringDaysOff.contains(normalized.weekday)) return false;
    return !exceptionDaysOff.any((d) =>
        d.year == normalized.year && d.month == normalized.month && d.day == normalized.day);
  }

  Map<String, dynamic> toJson() => {
        'recurringDaysOff': recurringDaysOff.toList(),
        'exceptionDaysOff': exceptionDaysOff
            .map((d) => DateTime(d.year, d.month, d.day).toIso8601String())
            .toList(),
      };

  factory WorkingCalendar.fromJson(Map<String, dynamic> json) => WorkingCalendar(
        recurringDaysOff:
            (json['recurringDaysOff'] as List<dynamic>? ?? []).cast<int>().toSet(),
        exceptionDaysOff: (json['exceptionDaysOff'] as List<dynamic>? ?? [])
            .map((s) => DateTime.parse(s as String))
            .toSet(),
      );
}

/// One goal — always carries both a target word count and a deadline
/// (see [GoalTargetType]'s doc comment for why). [startingWordCount] is
/// auto-detected from the manuscript at creation time so goals don't
/// double-count words already written (PLAN.md).
class Goal {
  final String id;
  final GoalScope scope;

  /// Only meaningful when [scope] is [GoalScope.global]: project ids to
  /// include. Null or empty means every project in the library.
  final List<String>? projectIds;

  final GoalTargetType targetType;
  final int targetWordCount;
  final DateTime deadline;
  final int startingWordCount;
  final DateTime created;
  final WorkingCalendar calendar;
  final bool active;

  /// date (yyyy-MM-dd) -> total word count in scope recorded at/after that
  /// date. Used for the heatmap and to compute words written on a given day
  /// (today's snapshot minus yesterday's).
  final Map<String, int> dailyLog;

  const Goal({
    required this.id,
    required this.scope,
    this.projectIds,
    required this.targetType,
    required this.targetWordCount,
    required this.deadline,
    required this.startingWordCount,
    required this.created,
    this.calendar = const WorkingCalendar(),
    this.active = true,
    this.dailyLog = const {},
  });

  Goal copyWith({bool? active, Map<String, int>? dailyLog}) => Goal(
        id: id,
        scope: scope,
        projectIds: projectIds,
        targetType: targetType,
        targetWordCount: targetWordCount,
        deadline: deadline,
        startingWordCount: startingWordCount,
        created: created,
        calendar: calendar,
        active: active ?? this.active,
        dailyLog: dailyLog ?? this.dailyLog,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'scope': scope.name,
        if (projectIds != null) 'projectIds': projectIds,
        'targetType': targetType.name,
        'targetWordCount': targetWordCount,
        'deadline': deadline.toIso8601String(),
        'startingWordCount': startingWordCount,
        'created': created.toIso8601String(),
        'calendar': calendar.toJson(),
        'active': active,
        'dailyLog': dailyLog,
      };

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
        id: json['id'] as String,
        scope: GoalScope.values.firstWhere(
          (s) => s.name == json['scope'],
          // Legacy goals created when act/scene scoping existed collapse to
          // whole-project rather than failing to load.
          orElse: () => GoalScope.project,
        ),
        projectIds: (json['projectIds'] as List<dynamic>?)?.cast<String>(),
        targetType:
            GoalTargetType.values.firstWhere((t) => t.name == json['targetType']),
        targetWordCount: json['targetWordCount'] as int,
        deadline: DateTime.parse(json['deadline'] as String),
        startingWordCount: json['startingWordCount'] as int,
        created: DateTime.parse(json['created'] as String),
        calendar: json['calendar'] == null
            ? const WorkingCalendar()
            : WorkingCalendar.fromJson(json['calendar'] as Map<String, dynamic>),
        active: json['active'] as bool? ?? true,
        dailyLog: (json['dailyLog'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v as int)),
      );
}
