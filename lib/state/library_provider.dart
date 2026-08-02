import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/archived_project.dart';
import '../models/project.dart';
import '../models/series.dart';
import '../services/library_service.dart';
import '../services/series_service.dart';

final libraryServiceProvider = Provider<LibraryService>(
  (ref) => LibraryService(),
);

/// The list of projects in the local library. Call `ref.invalidate(projectListProvider)`
/// after creating/renaming a project to refresh.
final projectListProvider = FutureProvider<List<Project>>((ref) async {
  final service = ref.watch(libraryServiceProvider);
  return service.listProjects();
});

/// Archived/soft-deleted project records — see `LibraryService.archiveProject`/
/// `deleteProject`. Call `ref.invalidate(...)` on the relevant one after
/// archiving, deleting, or restoring.
final archivedProjectsProvider = FutureProvider<List<ArchivedProject>>((
  ref,
) async {
  final service = ref.watch(libraryServiceProvider);
  return service.listArchived();
});

final deletedProjectsProvider = FutureProvider<List<ArchivedProject>>((
  ref,
) async {
  final service = ref.watch(libraryServiceProvider);
  return service.listDeleted();
});

/// The project currently open in the shell (null = library/home view).
final currentProjectProvider = StateProvider<Project?>((ref) => null);

/// The series a project was opened *from*, if any — lets the project shell's
/// back button return to that series' screen instead of always landing on
/// the top-level library. Set alongside [currentProjectProvider] wherever a
/// project is opened (series grid vs. the plain library grid decide whether
/// this is a series or null), and consumed once by the back button, which is
/// also responsible for clearing it back to null afterward.
final currentSeriesProvider = StateProvider<Series?>((ref) => null);

final seriesServiceProvider = Provider<SeriesService>(
  (ref) => SeriesService(ref.watch(libraryServiceProvider)),
);

/// The list of series in the local library. Call `ref.invalidate(seriesListProvider)`
/// after creating/renaming/deleting a series to refresh.
final seriesListProvider = FutureProvider<List<Series>>((ref) async {
  final service = ref.watch(seriesServiceProvider);
  return service.listSeries();
});

/// The series a project belongs to, or null for a standalone project. Used
/// by the Reference Panel to decide whether to show a "Series" tab at all.
final projectSeriesProvider = FutureProvider.family<Series?, Project>((
  ref,
  project,
) async {
  final seriesId = project.seriesId;
  if (seriesId == null) return null;
  final allSeries = await ref.watch(seriesListProvider.future);
  for (final series in allSeries) {
    if (series.id == seriesId) return series;
  }
  return null;
});

/// Every project belonging to [series], sorted the same as the library
/// grid's own project list — used by the "move to project" picker when
/// demoting a series-level entry back into one of its member projects.
final seriesProjectsProvider = FutureProvider.family<List<Project>, Series>((
  ref,
  series,
) async {
  final projects = await ref.watch(projectListProvider.future);
  return projects.where((p) => p.seriesId == series.id).toList();
});
