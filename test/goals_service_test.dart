import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/goal.dart';
import 'package:narraity/models/manuscript.dart';
import 'package:narraity/services/goals_service.dart';
import 'package:narraity/services/manuscript_service.dart';

void main() {
  late Directory tempDir;
  late ManuscriptService manuscriptService;
  late GoalsService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_goals_test_');
    manuscriptService = ManuscriptService(tempDir);
    service = GoalsService(tempDir, manuscriptService);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('a new project has no goals', () async {
    expect(await service.listGoals(), isEmpty);
  });

  test('createGoal auto-detects the starting word count from the manuscript', () async {
    final structure = await manuscriptService.loadStructure();
    final sceneId = structure.nodes.first.children.first.children.first.id;
    await manuscriptService.writeScene(
      SceneDoc(id: sceneId, title: 'Scene 1', content: 'one two three four five'),
    );

    final goal = await service.createGoal(
      targetType: GoalTargetType.deadline,
      targetWordCount: 1000,
      deadline: DateTime(2026, 12, 31),
    );

    expect(goal.scope, GoalScope.project);
    expect(goal.startingWordCount, 5);
  });

  test('createGoal persists and listGoals reads it back', () async {
    final goal = await service.createGoal(
      targetType: GoalTargetType.wordCount,
      targetWordCount: 50000,
      deadline: DateTime(2026, 11, 1),
      calendar: const WorkingCalendar(recurringDaysOff: {6, 7}),
    );

    final goals = await service.listGoals();
    expect(goals.single.id, goal.id);
    expect(goals.single.targetWordCount, 50000);
    expect(goals.single.calendar.recurringDaysOff, {6, 7});
  });

  test('currentWordCount sums every scene in the project', () async {
    final structure = await manuscriptService.loadStructure();
    final scene1Id = structure.nodes.first.children.first.children.first.id;
    await manuscriptService.writeScene(
      SceneDoc(id: scene1Id, title: 'S1', content: 'one two three'),
    );
    final chapter = structure.nodes.first.children.first;
    final scene2 = await manuscriptService.addNode(structure,
        typeLabel: 'Scene', parent: chapter);
    await manuscriptService.writeScene(
      SceneDoc(id: scene2.id, title: 'S2', content: 'four five six seven'),
    );

    expect(await service.currentWordCount(), 7);
  });

  test('recordTodaysProgress upserts today\'s total into the daily log', () async {
    final goal = await service.createGoal(
      targetType: GoalTargetType.deadline,
      targetWordCount: 1000,
      deadline: DateTime(2026, 12, 31),
    );

    final structure = await manuscriptService.loadStructure();
    final sceneId = structure.nodes.first.children.first.children.first.id;
    await manuscriptService.writeScene(
      SceneDoc(id: sceneId, title: 'Scene 1', content: 'one two three'),
    );

    final updated = await service.recordTodaysProgress(goal);
    expect(updated.dailyLog.values.single, 3);

    final reloaded = (await service.listGoals()).single;
    expect(reloaded.dailyLog.values.single, 3);
  });

  test('deleteGoal removes it', () async {
    final goal = await service.createGoal(
      targetType: GoalTargetType.deadline,
      targetWordCount: 1000,
      deadline: DateTime(2026, 12, 31),
    );
    await service.deleteGoal(goal.id);
    expect(await service.listGoals(), isEmpty);
  });

  test('setActive can pause a goal without deleting it', () async {
    final goal = await service.createGoal(
      targetType: GoalTargetType.deadline,
      targetWordCount: 1000,
      deadline: DateTime(2026, 12, 31),
    );
    await service.setActive(goal.id, false);

    final reloaded = (await service.listGoals()).single;
    expect(reloaded.active, isFalse);
  });
}
