import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/manuscript.dart';
import '../models/plot_grid.dart';
import '../models/project.dart';
import '../services/plot_grid_service.dart';
import 'library_provider.dart';
import 'manuscript_provider.dart';

final plotGridServiceProvider =
    FutureProvider.family<PlotGridService, Project>((ref, project) async {
  final root = await ref.watch(libraryServiceProvider).libraryRoot();
  return PlotGridService(Directory(p.join(root.path, project.folderName)));
});

final plotlineListProvider =
    FutureProvider.family<List<PlotLine>, Project>((ref, project) async {
  final service = await ref.watch(plotGridServiceProvider(project).future);
  return service.listPlotlines();
});

final plotPointListProvider =
    FutureProvider.family<List<PlotPoint>, Project>((ref, project) async {
  final service = await ref.watch(plotGridServiceProvider(project).future);
  return service.listPlotPoints();
});

/// Scene ids in manuscript order plus their titles — the grid's columns.
/// Built here rather than duplicated per-caller (project_shell_screen and
/// ManuscriptService both already do their own version of this walk).
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

/// Refreshes every list the Plot Grid screen shows. Call after any write
/// rather than invalidating providers ad hoc at each call site.
void invalidatePlotGrid(WidgetRef ref, Project project) {
  ref.invalidate(plotlineListProvider(project));
  ref.invalidate(plotPointListProvider(project));
}
