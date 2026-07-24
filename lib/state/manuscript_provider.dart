import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/manuscript.dart';
import '../models/project.dart';
import '../models/todo_item.dart';
import '../services/manuscript_service.dart';
import '../services/todo_service.dart';
import 'library_provider.dart';

/// Manuscript + todo services for a given project. Family-keyed by project so
/// switching projects gets fresh instances rooted at the right folder.
final manuscriptServiceProvider =
    FutureProvider.family<ManuscriptService, Project>((ref, project) async {
  final root = await ref.watch(libraryServiceProvider).libraryRoot();
  return ManuscriptService(Directory(p.join(root.path, project.folderName)));
});

final todoServiceProvider =
    FutureProvider.family<TodoService, Project>((ref, project) async {
  final root = await ref.watch(libraryServiceProvider).libraryRoot();
  return TodoService(Directory(p.join(root.path, project.folderName)));
});

final manuscriptStructureProvider =
    FutureProvider.family<ManuscriptStructure, Project>((ref, project) async {
  final service = await ref.watch(manuscriptServiceProvider(project).future);
  return service.loadStructure();
});

/// Id of the scene/section open in the editor (null = nothing selected yet).
final openContentIdProvider = StateProvider<String?>((ref) => null);

/// Focus Mode hides the sidebar and toolbar chrome for distraction-free writing.
final focusModeProvider = StateProvider<bool>((ref) => false);

final todoListProvider =
    FutureProvider.family<List<TodoItem>, Project>((ref, project) async {
  final service = await ref.watch(todoServiceProvider(project).future);
  return service.listTodos();
});
