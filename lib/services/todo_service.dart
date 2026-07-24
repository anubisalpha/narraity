import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/todo_item.dart';

const _uuid = Uuid();

/// Reads/writes a project's `todos/todos.json` (created empty in Phase 0).
class TodoService {
  TodoService(this.projectDir);

  final Directory projectDir;

  File get _file => File(p.join(projectDir.path, 'todos', 'todos.json'));

  Future<List<TodoItem>> listTodos() async {
    if (!await _file.exists()) return [];
    try {
      final json = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      return (json['todos'] as List<dynamic>? ?? [])
          .map((t) => TodoItem.fromJson(t as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<TodoItem> addTodo(String text,
      {TodoPriority priority = TodoPriority.normal, String? linkedSceneId}) async {
    final todos = await listTodos();
    final todo = TodoItem(
      id: 'todo-${_uuid.v4()}',
      text: text,
      priority: priority,
      linkedSceneId: linkedSceneId,
    );
    todos.add(todo);
    await _save(todos);
    return todo;
  }

  Future<void> updateTodo(TodoItem updated) async {
    final todos = await listTodos();
    final index = todos.indexWhere((t) => t.id == updated.id);
    if (index == -1) return;
    todos[index] = updated;
    await _save(todos);
  }

  Future<void> deleteTodo(String id) async {
    final todos = await listTodos();
    todos.removeWhere((t) => t.id == id);
    await _save(todos);
  }

  Future<void> _save(List<TodoItem> todos) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(const JsonEncoder.withIndent('  ')
        .convert({'todos': todos.map((t) => t.toJson()).toList()}));
  }
}
