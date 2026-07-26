import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/project_file_watcher.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory projectDir;
  late StreamController<ProjectFileChangeEvent> controller;
  late List<String> changed;
  late ProjectFileWatcher watcher;

  setUp(() {
    projectDir = Directory.systemTemp.createTempSync('narraity_file_watcher_test_');
    controller = StreamController<ProjectFileChangeEvent>();
    changed = [];
    watcher = ProjectFileWatcher(
      projectDir,
      onFileChanged: changed.add,
      events: controller.stream,
      debounce: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    await watcher.dispose();
    await controller.close();
    projectDir.deleteSync(recursive: true);
  });

  void emit(String relativePath, {bool isDirectory = false}) {
    controller.add(ProjectFileChangeEvent(
      p.joinAll([projectDir.path, ...p.posix.split(relativePath)]),
      isDirectory: isDirectory,
    ));
  }

  test('reports a changed file as a posix-style relative path after the debounce', () async {
    emit('todos/todos.json');
    expect(changed, isEmpty); // not yet — still debouncing

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(changed, ['todos/todos.json']);
  });

  test('rapid repeated changes to the same file only report once', () async {
    emit('todos/todos.json');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    emit('todos/todos.json');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    emit('todos/todos.json');

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(changed, ['todos/todos.json']);
  });

  test('changes to different files each report independently', () async {
    emit('todos/todos.json');
    emit('goals/goals.json');

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(changed, unorderedEquals(['todos/todos.json', 'goals/goals.json']));
  });

  test('ignores directory events', () async {
    emit('manuscript/scenes', isDirectory: true);

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(changed, isEmpty);
  });

  test('ignores changes under .sync/', () async {
    emit('.sync/manifest.json');

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(changed, isEmpty);
  });

  test('ignores changes under .history_backup/', () async {
    emit('manuscript/scenes/.history_backup/x/entry.json');

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(changed, isEmpty);
  });

  test('dispose stops further reports', () async {
    await watcher.dispose();
    emit('todos/todos.json');

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(changed, isEmpty);
  });
}
