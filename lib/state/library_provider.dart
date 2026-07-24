import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../services/library_service.dart';

final libraryServiceProvider = Provider<LibraryService>((ref) => LibraryService());

/// The list of projects in the local library. Call `ref.invalidate(projectListProvider)`
/// after creating/renaming a project to refresh.
final projectListProvider = FutureProvider<List<Project>>((ref) async {
  final service = ref.watch(libraryServiceProvider);
  return service.listProjects();
});

/// The project currently open in the shell (null = library/home view).
final currentProjectProvider = StateProvider<Project?>((ref) => null);
