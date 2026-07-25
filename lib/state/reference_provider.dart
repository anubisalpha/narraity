import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/profile_entry.dart';
import '../models/project.dart';
import '../models/story_note.dart';
import '../services/profile_service.dart';
import '../services/story_notes_service.dart';
import 'library_provider.dart';
import 'manuscript_provider.dart';

/// Which kind of reference material is open in the main pane.
enum ReferenceKind { character, world, note }

/// The reference entry currently open, replacing the scene editor in the main
/// pane. Kept separate from `openContentIdProvider` (which tracks the open
/// scene) so switching to a character and back doesn't lose your place in the
/// manuscript.
class ReferenceSelection {
  const ReferenceSelection(this.kind, this.id);

  final ReferenceKind kind;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is ReferenceSelection && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

final openReferenceProvider = StateProvider<ReferenceSelection?>((ref) => null);

Directory _projectDir(Directory root, Project project) =>
    Directory(p.join(root.path, project.folderName));

final characterServiceProvider =
    FutureProvider.family<ProfileService, Project>((ref, project) async {
  final root = await ref.watch(libraryServiceProvider).libraryRoot();
  return ProfileService(_projectDir(root, project), ProfileKind.character);
});

final worldServiceProvider =
    FutureProvider.family<ProfileService, Project>((ref, project) async {
  final root = await ref.watch(libraryServiceProvider).libraryRoot();
  return ProfileService(_projectDir(root, project), ProfileKind.world);
});

/// One service instance per project, kept alive across rebuilds so its search
/// index isn't thrown away every time the notes panel repaints.
final storyNotesServiceProvider =
    FutureProvider.family<StoryNotesService, Project>((ref, project) async {
  final root = await ref.watch(libraryServiceProvider).libraryRoot();
  return StoryNotesService(_projectDir(root, project));
});

final characterListProvider =
    FutureProvider.family<List<ProfileEntry>, Project>((ref, project) async {
  final service = await ref.watch(characterServiceProvider(project).future);
  return service.list();
});

final worldListProvider =
    FutureProvider.family<List<ProfileEntry>, Project>((ref, project) async {
  final service = await ref.watch(worldServiceProvider(project).future);
  return service.list();
});

/// Distinct world categories in use — drives grouping and the category
/// autocomplete. Derived from the same list the panel shows, so it can't
/// disagree with it.
final worldCategoriesProvider =
    FutureProvider.family<List<String>, Project>((ref, project) async {
  final entries = await ref.watch(worldListProvider(project).future);
  final categories = entries
      .map((e) => e.category)
      .whereType<String>()
      .where((c) => c.trim().isNotEmpty)
      .toSet()
      .toList();
  categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return categories;
});

final storyNoteListProvider =
    FutureProvider.family<List<StoryNote>, Project>((ref, project) async {
  final service = await ref.watch(storyNotesServiceProvider(project).future);
  return service.listAll();
});

final noteFoldersProvider =
    FutureProvider.family<List<String>, Project>((ref, project) async {
  // Watching the note list as well means creating or moving a note refreshes
  // folders too, without every call site remembering to invalidate both.
  await ref.watch(storyNoteListProvider(project).future);
  final service = await ref.watch(storyNotesServiceProvider(project).future);
  return service.folders();
});

/// Current text in the notes search box. Empty means "not searching" — the
/// panel shows the folder tree instead of results.
final noteSearchQueryProvider = StateProvider<String>((ref) => '');

final noteSearchResultsProvider =
    FutureProvider.family<List<StoryNote>, Project>((ref, project) async {
  final query = ref.watch(noteSearchQueryProvider);
  if (query.trim().isEmpty) return [];
  // Depend on the note list so results refresh after an edit.
  await ref.watch(storyNoteListProvider(project).future);
  final service = await ref.watch(storyNotesServiceProvider(project).future);
  return service.search(query);
});

/// Opens a scene in the main pane, closing whatever reference entry was
/// showing there. Without the second half, tapping a scene while a character
/// profile is open would look like it did nothing.
void openScene(WidgetRef ref, String sceneId) {
  ref.read(openContentIdProvider.notifier).state = sceneId;
  ref.read(openReferenceProvider.notifier).state = null;
}

/// Refreshes every list a project's reference panels show. Call after any
/// write rather than invalidating providers ad hoc at each call site.
void invalidateReferences(WidgetRef ref, Project project) {
  ref.invalidate(characterListProvider(project));
  ref.invalidate(worldListProvider(project));
  ref.invalidate(storyNoteListProvider(project));
}
