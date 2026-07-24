import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/goal.dart';
import '../services/goal_calculator.dart';

String _scopeLabel(Goal goal) => switch (goal.scope) {
      GoalScope.project => 'Whole project',
      GoalScope.global => (goal.projectIds == null || goal.projectIds!.isEmpty)
          ? 'All projects'
          : '${goal.projectIds!.length} selected projects',
    };

/// One goal's progress: today-vs-overall rings, a lightweight calendar
/// heatmap of daily performance, and a note that targets adjust
/// automatically (PLAN.md: "subtle notice when a target has been
/// recalculated" — shown as a standing explanation rather than a one-off
/// event, since detecting "changed since last viewed" would need extra
/// state this v1 doesn't track).
///
/// Takes callbacks rather than a project + provider lookup so the same
/// widget serves both per-project goals (GoalsService) and app-wide goals
/// (GlobalGoalsService) without knowing which one it's talking to.
class GoalProgressCard extends StatelessWidget {
  const GoalProgressCard({
    super.key,
    required this.goal,
    required this.onRecordProgress,
    required this.onDelete,
  });

  final Goal goal;
  final Future<Goal> Function(Goal goal) onRecordProgress;
  final Future<void> Function(Goal goal) onDelete;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Goal>(
      // Recording today's progress on every view is what keeps the
      // heatmap/redistribution current.
      future: onRecordProgress(goal),
      builder: (context, snapshot) {
        final current = snapshot.data ?? goal;
        final currentWordCount = _mostRecentLoggedTotal(current);
        final progress = GoalCalculator.calculate(
          goal: current,
          currentWordCount: currentWordCount,
          today: DateTime.now(),
        );

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _scopeLabel(current),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (progress.isComplete)
                      const Chip(
                        avatar: Icon(Icons.celebration, size: 16),
                        label: Text('Complete!'),
                      )
                    else if (progress.isOverdue)
                      Chip(
                        avatar: const Icon(Icons.warning_amber, size: 16),
                        label: const Text('Overdue'),
                        backgroundColor: Theme.of(context).colorScheme.errorContainer,
                      ),
                    IconButton(
                      tooltip: 'Delete goal',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => onDelete(current),
                    ),
                  ],
                ),
                Text(
                  'Target: ${current.targetWordCount} words by '
                  '${DateFormat.yMMMd().format(current.deadline)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _ProgressRing(
                      label: 'Today',
                      fraction: progress.todayFraction,
                      caption: '${progress.wordsWrittenToday} / ${progress.dailyTarget}',
                    ),
                    const SizedBox(width: 24),
                    _ProgressRing(
                      label: 'Overall',
                      fraction: progress.overallFraction,
                      caption: '${progress.wordsWrittenSoFar} / ${progress.wordsToWrite}',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.autorenew, size: 14, color: Theme.of(context).hintColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Daily target recalculates automatically from your actual '
                        'progress — miss a day and it rises to compensate; get ahead '
                        'and it eases off.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Recent activity', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                _Heatmap(goal: current, dailyTarget: progress.dailyTarget),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The word-count total logged on the most recent date in the log —
  /// `Map.values.last` isn't safe here since Dart maps preserve insertion
  /// order, not date order, and updating an existing key's value doesn't
  /// move it to the end.
  int _mostRecentLoggedTotal(Goal goal) {
    if (goal.dailyLog.isEmpty) return goal.startingWordCount;
    DateTime? bestDate;
    int? bestValue;
    for (final entry in goal.dailyLog.entries) {
      final date = DateTime.parse(entry.key);
      if (bestDate == null || date.isAfter(bestDate)) {
        bestDate = date;
        bestValue = entry.value;
      }
    }
    return bestValue!;
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.label, required this.fraction, required this.caption});

  final String label;
  final double fraction;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: fraction,
                strokeWidth: 6,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              Text('${(fraction * 100).round()}%'),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Text(caption, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// Last 30 days, one square per day, colored by words-written-that-day vs
/// that goal's *current* daily target — a lightweight stand-in for a full
/// calendar-month grid (PLAN.md "calendar heatmap of daily performance").
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.goal, required this.dailyTarget});

  final Goal goal;
  final int dailyTarget;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(30, (i) => today.subtract(Duration(days: 29 - i)));

    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (final day in days) _HeatmapCell(day: day, goal: goal, dailyTarget: dailyTarget),
      ],
    );
  }
}

class _HeatmapCell extends StatelessWidget {
  const _HeatmapCell({required this.day, required this.goal, required this.dailyTarget});

  final DateTime day;
  final Goal goal;
  final int dailyTarget;

  @override
  Widget build(BuildContext context) {
    final key =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final logged = goal.dailyLog[key];

    Color color;
    if (logged == null) {
      color = Theme.of(context).colorScheme.surfaceContainerHighest;
    } else {
      final previous = _totalBefore(day);
      final written = (logged - previous).clamp(0, 1 << 31);
      if (dailyTarget <= 0 || written >= dailyTarget) {
        color = Colors.green;
      } else if (written > 0) {
        color = Colors.orange;
      } else {
        color = Colors.red.shade200;
      }
    }

    return Tooltip(
      message: '${DateFormat.yMMMd().format(day)}${logged == null ? '' : ': logged'}',
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
    );
  }

  int _totalBefore(DateTime day) {
    DateTime? bestDate;
    int? bestValue;
    for (final entry in goal.dailyLog.entries) {
      final date = DateTime.parse(entry.key);
      if (!date.isBefore(day)) continue;
      if (bestDate == null || date.isAfter(bestDate)) {
        bestDate = date;
        bestValue = entry.value;
      }
    }
    return bestValue ?? goal.startingWordCount;
  }
}
