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

/// Scene ids in manuscript order plus their titles — used anywhere a feature
/// needs to list or link to scenes (Plot Grid columns, Timeline event
/// linking) without re-walking the tree itself.
final sceneColumnsProvider =
    FutureProvider.family<List<(String id, String title)>, Project>((ref, project) async {
  final structure = await ref.watch(manuscriptStructureProvider(project).future);

  final titles = <String, String>{};
  for (final section in [...structure.frontMatter, ...structure.backMatter]) {
    titles[section.id] = section.title;
  }
  void collect(List<ManuscriptNode> nodes) {
    for (final node in nodes) {
      titles[node.id] = node.title;
      collect(node.children);
    }
  }

  collect(structure.nodes);
  return [for (final id in structure.allContentIds) (id, titles[id] ?? 'Untitled')];
});
