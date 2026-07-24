import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/goal.dart';
import 'package:narraity/models/manuscript.dart';
import 'package:narraity/services/global_goals_service.dart';
import 'package:narraity/services/library_service.dart';
import 'package:narraity/services/manuscript_service.dart';

void main() {
  late Directory tempDir;
  late LibraryService library;
  late GlobalGoalsService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_global_goals_test_');
    library = LibraryService(rootOverride: tempDir);
    service = GlobalGoalsService(library);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<void> writeWords(String folderName, String content) async {
    final projectDir = Directory('${tempDir.path}/$folderName');
    final manuscript = ManuscriptService(projectDir);
    final structure = await manuscript.loadStructure();
    final sceneId = structure.nodes.first.children.first.children.first.id;
    await manuscript.writeScene(SceneDoc(id: sceneId, title: 'S1', content: content));
  }

  test('a fresh library has no global goals', () async {
    expect(await service.listGoals(), isEmpty);
  });

  test('currentWordCount(null) sums every project in the library', () async {
    final a = await library.createProject(title: 'Novel A');
    final b = await library.createProject(title: 'Novel B');
    await writeWords(a.folderName, 'one two three');
    await writeWords(b.folderName, 'four five');

    expect(await service.currentWordCount(null), 5);
  });

  test('currentWordCount with specific project ids only sums those', () async {
    final a = await library.createProject(title: 'Novel A');
    final b = await library.createProject(title: 'Novel B');
    await writeWords(a.folderName, 'one two three');
    await writeWords(b.folderName, 'four five');

    expect(await service.currentWordCount([a.id]), 3);
  });

  test('createGoal auto-detects starting word count across all projects', () async {
    final a = await library.createProject(title: 'Novel A');
    await writeWords(a.folderName, 'one two three four');

    final goal = await service.createGoal(
      targetType: GoalTargetType.deadline,
      targetWordCount: 100000,
      deadline: DateTime(2027, 1, 1),
    );

    expect(goal.scope, GoalScope.global);
    expect(goal.startingWordCount, 4);
    expect(goal.projectIds, isNull);
  });

  test('goals persist to _GlobalGoals/goals.json at the library root', () async {
    await service.createGoal(
      targetType: GoalTargetType.wordCount,
      targetWordCount: 50000,
      deadline: DateTime(2027, 1, 1),
    );

    expect(File('${tempDir.path}/_GlobalGoals/goals.json').existsSync(), isTrue);
    expect(await service.listGoals(), hasLength(1));
  });

  test('a goal scoped to specific projects only counts those toward progress', () async {
    final a = await library.createProject(title: 'Novel A');
    final b = await library.createProject(title: 'Novel B');
    await writeWords(a.folderName, 'one two');

    final goal = await service.createGoal(
      targetType: GoalTargetType.deadline,
      targetWordCount: 1000,
      deadline: DateTime(2027, 1, 1),
      projectIds: [a.id],
    );

    await writeWords(b.folderName, 'three four five'); // shouldn't count

    final updated = await service.recordTodaysProgress(goal);
    expect(updated.dailyLog.values.single, 2);
  });

  test('deleteGoal removes it', () async {
    final goal = await service.createGoal(
      targetType: GoalTargetType.deadline,
      targetWordCount: 1000,
      deadline: DateTime(2027, 1, 1),
    );
    await service.deleteGoal(goal.id);
    expect(await service.listGoals(), isEmpty);
  });
}
