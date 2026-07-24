import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/goal.dart';
import 'package:narraity/services/goal_calculator.dart';

Goal _goal({
  required int targetWordCount,
  required DateTime deadline,
  int startingWordCount = 0,
  WorkingCalendar calendar = const WorkingCalendar(),
  Map<String, int> dailyLog = const {},
}) {
  return Goal(
    id: 'goal-1',
    scope: GoalScope.project,
    targetType: GoalTargetType.deadline,
    targetWordCount: targetWordCount,
    deadline: deadline,
    startingWordCount: startingWordCount,
    created: DateTime(2026, 1, 1),
    calendar: calendar,
    dailyLog: dailyLog,
  );
}

void main() {
  group('workingDaysBetween', () {
    test('inclusive of both start and end with no days off', () {
      final days = GoalCalculator.workingDaysBetween(
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 5),
        const WorkingCalendar(),
      );
      expect(days, 5);
    });

    test('excludes recurring days off (weekends)', () {
      // 2026-01-05 is a Monday; +6 days = Sunday 2026-01-11.
      final days = GoalCalculator.workingDaysBetween(
        DateTime(2026, 1, 5),
        DateTime(2026, 1, 11),
        const WorkingCalendar(recurringDaysOff: {6, 7}), // Sat, Sun
      );
      expect(days, 5); // Mon-Fri
    });

    test('excludes one-off exception days', () {
      final days = GoalCalculator.workingDaysBetween(
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 5),
        WorkingCalendar(exceptionDaysOff: {DateTime(2026, 1, 3)}),
      );
      expect(days, 4);
    });

    test('returns 0 when end is before start', () {
      final days = GoalCalculator.workingDaysBetween(
        DateTime(2026, 1, 5),
        DateTime(2026, 1, 1),
        const WorkingCalendar(),
      );
      expect(days, 0);
    });
  });

  group('GoalCalculator.calculate', () {
    test('basic daily target: fresh goal, no words written yet', () {
      final goal = _goal(targetWordCount: 10000, deadline: DateTime(2026, 1, 5));
      final progress = GoalCalculator.calculate(
        goal: goal,
        currentWordCount: 0,
        today: DateTime(2026, 1, 1),
      );
      expect(progress.wordsToWrite, 10000);
      expect(progress.remainingWords, 10000);
      expect(progress.remainingWorkingDays, 5);
      expect(progress.dailyTarget, 2000);
      expect(progress.isComplete, isFalse);
    });

    test('auto-detected starting word count is not double-counted', () {
      final goal = _goal(
        targetWordCount: 10000,
        startingWordCount: 3000,
        deadline: DateTime(2026, 1, 5),
      );
      final progress = GoalCalculator.calculate(
        goal: goal,
        currentWordCount: 3000, // hasn't written anything new yet
        today: DateTime(2026, 1, 1),
      );
      expect(progress.wordsToWrite, 7000);
      expect(progress.remainingWords, 7000);
    });

    test('a missed day raises tomorrow\'s target automatically', () {
      final goal = _goal(targetWordCount: 10000, deadline: DateTime(2026, 1, 10));
      // Day 1 (Jan 1): target would be 10000/10 = 1000, but nothing gets written.
      final day1 = GoalCalculator.calculate(
        goal: goal,
        currentWordCount: 0,
        today: DateTime(2026, 1, 1),
      );
      expect(day1.dailyTarget, 1000);

      // Day 2: word count still 0, one fewer working day left.
      final day2 = GoalCalculator.calculate(
        goal: goal,
        currentWordCount: 0,
        today: DateTime(2026, 1, 2),
      );
      expect(day2.remainingWorkingDays, 9);
      expect(day2.dailyTarget, greaterThan(day1.dailyTarget));
      expect(day2.dailyTarget, (10000 / 9).ceil());
    });

    test('an over-target day lowers tomorrow\'s target automatically', () {
      final goal = _goal(targetWordCount: 10000, deadline: DateTime(2026, 1, 10));
      final day1 = GoalCalculator.calculate(
        goal: goal,
        currentWordCount: 0,
        today: DateTime(2026, 1, 1),
      );
      expect(day1.dailyTarget, 1000);

      // Wrote 3000 words on day 1 — way over the 1000 target.
      final day2 = GoalCalculator.calculate(
        goal: goal,
        currentWordCount: 3000,
        today: DateTime(2026, 1, 2),
      );
      expect(day2.remainingWords, 7000);
      expect(day2.dailyTarget, lessThan(day1.dailyTarget));
      expect(day2.dailyTarget, (7000 / 9).ceil());
    });

    test('isComplete once remaining words hits zero', () {
      final goal = _goal(targetWordCount: 10000, deadline: DateTime(2026, 1, 10));
      final progress = GoalCalculator.calculate(
        goal: goal,
        currentWordCount: 10000,
        today: DateTime(2026, 1, 5),
      );
      expect(progress.isComplete, isTrue);
      expect(progress.remainingWords, 0);
    });

    test('isOverdue when the deadline has passed with words still remaining', () {
      final goal = _goal(targetWordCount: 10000, deadline: DateTime(2026, 1, 5));
      final progress = GoalCalculator.calculate(
        goal: goal,
        currentWordCount: 2000,
        today: DateTime(2026, 1, 10),
      );
      expect(progress.isOverdue, isTrue);
      expect(progress.remainingWorkingDays, 0);
      // Nothing left to spread the remainder over — dump it all into "today".
      expect(progress.dailyTarget, 8000);
    });

    test('a finished goal past its deadline is complete, not overdue', () {
      final goal = _goal(targetWordCount: 10000, deadline: DateTime(2026, 1, 5));
      final progress = GoalCalculator.calculate(
        goal: goal,
        currentWordCount: 10000,
        today: DateTime(2026, 1, 10),
      );
      expect(progress.isComplete, isTrue);
      expect(progress.isOverdue, isFalse);
    });

    test('wordsWrittenToday reads from the daily log diff', () {
      final goal = _goal(
        targetWordCount: 10000,
        deadline: DateTime(2026, 1, 10),
        dailyLog: const {'2026-01-01': 500, '2026-01-02': 1300},
      );
      final progress = GoalCalculator.calculate(
        goal: goal,
        currentWordCount: 1300,
        today: DateTime(2026, 1, 2),
      );
      expect(progress.wordsWrittenToday, 800); // 1300 - 500
    });

    test('a working-day deadline with zero remaining days dumps into today', () {
      // Deadline is a Sunday, marked off — no working days remain, but the
      // goal isn't overdue yet (today == deadline).
      final goal = _goal(
        targetWordCount: 1000,
        deadline: DateTime(2026, 1, 4), // Sunday
        calendar: const WorkingCalendar(recurringDaysOff: {7}),
      );
      final progress = GoalCalculator.calculate(
        goal: goal,
        currentWordCount: 0,
        today: DateTime(2026, 1, 4),
      );
      expect(progress.remainingWorkingDays, 0);
      expect(progress.dailyTarget, 1000);
    });
  });
}
