import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/todo_item.dart';
import 'package:narraity/services/todo_service.dart';

void main() {
  late Directory tempDir;
  late TodoService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_todo_test_');
    service = TodoService(tempDir);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('empty project has no todos', () async {
    expect(await service.listTodos(), isEmpty);
  });

  test('addTodo persists to todos/todos.json and round-trips', () async {
    await service.addTodo("Fix Elena's eye colour", priority: TodoPriority.high);

    expect(File('${tempDir.path}/todos/todos.json').existsSync(), isTrue);
    final todos = await service.listTodos();
    expect(todos.single.text, "Fix Elena's eye colour");
    expect(todos.single.priority, TodoPriority.high);
    expect(todos.single.done, isFalse);
  });

  test('updateTodo toggles done state', () async {
    final todo = await service.addTodo('Write chapter 2');
    await service.updateTodo(todo.copyWith(done: true));

    final reloaded = await service.listTodos();
    expect(reloaded.single.done, isTrue);
  });

  test('deleteTodo removes only the targeted item', () async {
    final keep = await service.addTodo('Keep me');
    final drop = await service.addTodo('Delete me');

    await service.deleteTodo(drop.id);

    final remaining = await service.listTodos();
    expect(remaining.single.id, keep.id);
  });

  test('linkedSceneId survives the round-trip', () async {
    await service.addTodo('Revise opening', linkedSceneId: 'scene-abc');
    final todos = await service.listTodos();
    expect(todos.single.linkedSceneId, 'scene-abc');
  });
}
