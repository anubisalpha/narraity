import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/plot_grid.dart';
import '../models/project.dart';
import '../services/plot_grid_service.dart';
import 'library_provider.dart';

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

/// Refreshes every list the Plot Grid screen shows. Call after any write
/// rather than invalidating providers ad hoc at each call site.
void invalidatePlotGrid(WidgetRef ref, Project project) {
  ref.invalidate(plotlineListProvider(project));
  ref.invalidate(plotPointListProvider(project));
}
