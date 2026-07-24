import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/idea.dart';
import '../services/ideas_service.dart';
import 'library_provider.dart';

final ideasServiceProvider = Provider<IdeasService>(
  (ref) => IdeasService(ref.watch(libraryServiceProvider)),
);

/// All captured ideas, newest first. Invalidate after capture/edit/promote.
final ideaListProvider = FutureProvider<List<Idea>>((ref) async {
  final service = ref.watch(ideasServiceProvider);
  return service.listIdeas();
});

/// Free-text filter applied to the ideas list.
final ideaSearchProvider = StateProvider<String>((ref) => '');

/// Active tag filter (null = all tags).
final ideaTagFilterProvider = StateProvider<String?>((ref) => null);
