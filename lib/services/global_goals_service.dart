import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/goal.dart';
import 'library_service.dart';
import 'manuscript_service.dart';

const _uuid = Uuid();

/// Reads/writes app-wide goals (`_GlobalGoals/goals.json` at the library
/// root, alongside `_GlobalIdeas/`) — goals that track word count across
/// multiple projects rather than one. [Goal.projectIds] optionally narrows
/// which projects count; null/empty means every project in the library.
class GlobalGoalsService {
  GlobalGoalsService(this._library);

  final LibraryService _library;

  Future<Directory> _goalsDir() async {
    final root = await _library.libraryRoot();
    final dir = Directory(p.join(root.path, '_GlobalGoals'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _file() async => File(p.join((await _goalsDir()).path, 'goals.json'));

  Future<List<Goal>> listGoals() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return (json['goals'] as List<dynamic>? ?? [])
          .map((g) => Goal.fromJson(g as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Sums word count across every project in [projectIds], or every project
  /// in the library if null/empty.
  Future<int> currentWordCount(List<String>? projectIds) async {
    final root = await _library.libraryRoot();
    final allProjects = await _library.listProjects();
    final included = (projectIds == null || projectIds.isEmpty)
        ? allProjects
        : allProjects.where((p) => projectIds.contains(p.id));

    var total = 0;
    for (final project in included) {
      final manuscriptService =
          ManuscriptService(Directory(p.join(root.path, project.folderName)));
      final structure = await manuscriptService.loadStructure();
      total += await manuscriptService.totalWordCount(structure);
    }
    return total;
  }

  Future<Goal> createGoal({
    required GoalTargetType targetType,
    required int targetWordCount,
    required DateTime deadline,
    List<String>? projectIds,
    WorkingCalendar calendar = const WorkingCalendar(),
  }) async {
    final starting = await currentWordCount(projectIds);
    final goal = Goal(
      id: _uuid.v4(),
      scope: GoalScope.global,
      projectIds: projectIds,
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

  Future<Goal> recordTodaysProgress(Goal goal) async {
    final total = await currentWordCount(goal.projectIds);
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
    final file = await _file();
    await file.writeAsString(const JsonEncoder.withIndent('  ')
        .convert({'goals': goals.map((g) => g.toJson()).toList()}));
  }
}
