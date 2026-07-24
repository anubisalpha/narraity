import '../models/goal.dart';

/// A snapshot of where a goal stands right now.
class GoalProgress {
  final int wordsToWrite; // targetWordCount - startingWordCount
  final int wordsWrittenSoFar; // currentWordCount - startingWordCount
  final int remainingWords; // clamped at 0
  final int remainingWorkingDays; // today..deadline inclusive, minus days off
  final int dailyTarget; // remainingWords / remainingWorkingDays, ceiling
  final int wordsWrittenToday;
  final bool isComplete;
  final bool isOverdue;

  const GoalProgress({
    required this.wordsToWrite,
    required this.wordsWrittenSoFar,
    required this.remainingWords,
    required this.remainingWorkingDays,
    required this.dailyTarget,
    required this.wordsWrittenToday,
    required this.isComplete,
    required this.isOverdue,
  });

  double get overallFraction =>
      wordsToWrite <= 0 ? 1.0 : (wordsWrittenSoFar / wordsToWrite).clamp(0.0, 1.0);

  double get todayFraction =>
      dailyTarget <= 0 ? 1.0 : (wordsWrittenToday / dailyTarget).clamp(0.0, 1.0);
}

/// The Adaptive Goal Engine's math (PLAN.md "Adaptive Goal Engine"). Pure
/// and deterministic — takes a [Goal] plus the current word count and
/// "today" as inputs, so it's fully unit-testable without touching disk.
///
/// The redistribution behaviour PLAN.md describes ("missed days redistribute
/// the shortfall", "over-target days reduce future targets") isn't separate
/// bookkeeping — it falls straight out of recalculating
/// `remaining words ÷ remaining working days` fresh every day from the
/// *actual* current word count. Miss a day and remainingWords stays high
/// while remainingWorkingDays drops, so tomorrow's target rises on its own;
/// overshoot and the opposite happens. Nothing else is needed.
class GoalCalculator {
  GoalCalculator._();

  static GoalProgress calculate({
    required Goal goal,
    required int currentWordCount,
    required DateTime today,
  }) {
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final wordsToWrite = (goal.targetWordCount - goal.startingWordCount).clamp(0, 1 << 31);
    final wordsWrittenSoFar =
        (currentWordCount - goal.startingWordCount).clamp(0, 1 << 31);
    final remainingWords = (wordsToWrite - wordsWrittenSoFar).clamp(0, 1 << 31);

    final deadline =
        DateTime(goal.deadline.year, goal.deadline.month, goal.deadline.day);
    final isOverdue = normalizedToday.isAfter(deadline) && remainingWords > 0;
    final remainingWorkingDays =
        isOverdue ? 0 : workingDaysBetween(normalizedToday, deadline, goal.calendar);

    final dailyTarget = remainingWorkingDays <= 0
        ? remainingWords
        : (remainingWords / remainingWorkingDays).ceil();

    final todayKey = _dateKey(normalizedToday);
    final yesterdayEntry = _mostRecentEntryBefore(goal.dailyLog, normalizedToday);
    final todaysLoggedTotal = goal.dailyLog[todayKey];
    final wordsWrittenToday = todaysLoggedTotal == null
        ? 0
        : (todaysLoggedTotal - (yesterdayEntry ?? goal.startingWordCount))
            .clamp(0, 1 << 31);

    return GoalProgress(
      wordsToWrite: wordsToWrite,
      wordsWrittenSoFar: wordsWrittenSoFar,
      remainingWords: remainingWords,
      remainingWorkingDays: remainingWorkingDays,
      dailyTarget: dailyTarget,
      wordsWrittenToday: wordsWrittenToday,
      isComplete: remainingWords <= 0,
      isOverdue: isOverdue,
    );
  }

  /// Counts working days from [start] to [end], inclusive of both ends,
  /// skipping days [calendar] marks as off. Returns 0 if [end] is before
  /// [start].
  static int workingDaysBetween(DateTime start, DateTime end, WorkingCalendar calendar) {
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEnd = DateTime(end.year, end.month, end.day);
    if (normalizedEnd.isBefore(normalizedStart)) return 0;

    var count = 0;
    var day = normalizedStart;
    while (!day.isAfter(normalizedEnd)) {
      if (calendar.isWorkingDay(day)) count++;
      day = day.add(const Duration(days: 1));
    }
    return count;
  }

  static String _dateKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  /// The word-count total logged on the most recent date strictly before
  /// [before], used as the baseline for "words written today".
  static int? _mostRecentEntryBefore(Map<String, int> dailyLog, DateTime before) {
    DateTime? bestDate;
    int? bestValue;
    for (final entry in dailyLog.entries) {
      final date = DateTime.parse(entry.key);
      if (!date.isBefore(before)) continue;
      if (bestDate == null || date.isAfter(bestDate)) {
        bestDate = date;
        bestValue = entry.value;
      }
    }
    return bestValue;
  }
}
