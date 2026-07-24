import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/goal.dart';
import 'manuscript_service.dart';

const _uuid = Uuid();

/// Reads/writes a project's `goals/goals.json` and computes the project's
/// current total word count from the manuscript — the "starting word count
/// auto-detected" and daily-log inputs the GoalCalculator needs (PLAN.md
/// "Adaptive Goal Engine"). Per-project goals always track the whole
/// project; see GlobalGoalsService for the app-wide counterpart.
class GoalsService {
  GoalsService(this.projectDir, this.manuscriptService);

  final Directory projectDir;
  final ManuscriptService manuscriptService;

  File get _file => File(p.join(projectDir.path, 'goals', 'goals.json'));

  Future<List<Goal>> listGoals() async {
    if (!await _file.exists()) return [];
    try {
      final json = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      return (json['goals'] as List<dynamic>? ?? [])
          .map((g) => Goal.fromJson(g as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// The project's current total word count — used both to auto-detect a
  /// new goal's starting count and to compute live progress.
  Future<int> currentWordCount() async {
    final structure = await manuscriptService.loadStructure();
    return manuscriptService.totalWordCount(structure);
  }

  Future<Goal> createGoal({
    required GoalTargetType targetType,
    required int targetWordCount,
    required DateTime deadline,
    WorkingCalendar calendar = const WorkingCalendar(),
  }) async {
    final starting = await currentWordCount();
    final goal = Goal(
      id: _uuid.v4(),
      scope: GoalScope.project,
      targetType: targetType,
      targetWordCount: targetWordCount,
      deadline: deadline,
      startingWordCount: starting,
      created: DateTime.now(),
      calendar: calendar,
    );
    final goals = await listGoals();
    goals.add(goal);
    await _save(goals);
    return goal;
  }

  Future<void> deleteGoal(String id) async {
    final goals = await listGoals();
    goals.removeWhere((g) => g.id == id);
    await _save(goals);
  }

  Future<void> setActive(String id, bool active) async {
    final goals = await listGoals();
    final index = goals.indexWhere((g) => g.id == id);
    if (index == -1) return;
    goals[index] = goals[index].copyWith(active: active);
    await _save(goals);
  }

  /// Records today's total word count into [goal]'s daily log (upsert) —
  /// call whenever the goal's progress is viewed so the heatmap and "words
  /// written today" figure stay current. Returns the updated goal.
  Future<Goal> recordTodaysProgress(Goal goal) async {
    final total = await currentWordCount();
    final today = DateTime.now();
    final key =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final updated = goal.copyWith(dailyLog: {...goal.dailyLog, key: total});
    final goals = await listGoals();
    final index = goals.indexWhere((g) => g.id == goal.id);
    if (index != -1) {
      goals[index] = updated;
      await _save(goals);
    }
    return updated;
  }

  Future<void> _save(List<Goal> goals) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(const JsonEncoder.withIndent('  ')
        .convert({'goals': goals.map((g) => g.toJson()).toList()}));
  }
}
