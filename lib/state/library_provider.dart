import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../models/series.dart';
import '../services/library_service.dart';
import '../services/series_service.dart';

final libraryServiceProvider = Provider<LibraryService>((ref) => LibraryService());

/// The list of projects in the local library. Call `ref.invalidate(projectListProvider)`
/// after creating/renaming a project to refresh.
final projectListProvider = FutureProvider<List<Project>>((ref) async {
  final service = ref.watch(libraryServiceProvider);
  return service.listProjects();
});

/// The project currently open in the shell (null = library/home view).
final currentProjectProvider = StateProvider<Project?>((ref) => null);

final seriesServiceProvider =
    Provider<SeriesService>((ref) => SeriesService(ref.watch(libraryServiceProvider)));

/// The list of series in the local library. Call `ref.invalidate(seriesListProvider)`
/// after creating/renaming/deleting a series to refresh.
final seriesListProvider = FutureProvider<List<Series>>((ref) async {
  final service = ref.watch(seriesServiceProvider);
  return service.listSeries();
});
