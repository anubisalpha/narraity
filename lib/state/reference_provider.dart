import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/content_owner.dart';
import '../models/profile_entry.dart';
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

Directory _ownerDir(Directory root, ContentOwner owner) =>
    Directory(p.join(root.path, owner.relativePath));

final characterServiceProvider =
    FutureProvider.family<ProfileService, ContentOwner>((ref, owner) async {
  final root = await ref.watch(libraryServiceProvider).libraryRoot();
  return ProfileService(_ownerDir(root, owner), ProfileKind.character);
});

final worldServiceProvider =
    FutureProvider.family<ProfileService, ContentOwner>((ref, owner) async {
  final root = await ref.watch(libraryServiceProvider).libraryRoot();
  return ProfileService(_ownerDir(root, owner), ProfileKind.world);
});

/// One service instance per owner, kept alive across rebuilds so its search
/// index isn't thrown away every time the notes panel repaints.
final storyNotesServiceProvider =
    FutureProvider.family<StoryNotesService, ContentOwner>((ref, owner) async {
  final root = await ref.watch(libraryServiceProvider).libraryRoot();
  return StoryNotesService(_ownerDir(root, owner));
});

final characterListProvider =
    FutureProvider.family<List<ProfileEntry>, ContentOwner>((ref, owner) async {
  final service = await ref.watch(characterServiceProvider(owner).future);
  return service.list();
});

final worldListProvider =
    FutureProvider.family<List<ProfileEntry>, ContentOwner>((ref, owner) async {
  final service = await ref.watch(worldServiceProvider(owner).future);
  return service.list();
});

/// Distinct world categories in use — drives grouping and the category
/// autocomplete. Derived from the same list the panel shows, so it can't
/// disagree with it.
final worldCategoriesProvider =
    FutureProvider.family<List<String>, ContentOwner>((ref, owner) async {
  final entries = await ref.watch(worldListProvider(owner).future);
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
    FutureProvider.family<List<StoryNote>, ContentOwner>((ref, owner) async {
  final service = await ref.watch(storyNotesServiceProvider(owner).future);
  return service.listAll();
});

final noteFoldersProvider =
    FutureProvider.family<List<String>, ContentOwner>((ref, owner) async {
  // Watching the note list as well means creating or moving a note refreshes
  // folders too, without every call site remembering to invalidate both.
  await ref.watch(storyNoteListProvider(owner).future);
  final service = await ref.watch(storyNotesServiceProvider(owner).future);
  return service.folders();
});

/// Current text in the notes search box. Empty means "not searching" — the
/// panel shows the folder tree instead of results.
final noteSearchQueryProvider = StateProvider<String>((ref) => '');

final noteSearchResultsProvider =
    FutureProvider.family<List<StoryNote>, ContentOwner>((ref, owner) async {
  final query = ref.watch(noteSearchQueryProvider);
  if (query.trim().isEmpty) return [];
  // Depend on the note list so results refresh after an edit.
  await ref.watch(storyNoteListProvider(owner).future);
  final service = await ref.watch(storyNotesServiceProvider(owner).future);
  return service.search(query);
});

/// Opens a scene in the main pane, closing whatever reference entry was
/// showing there. Without the second half, tapping a scene while a character
/// profile is open would look like it did nothing.
void openScene(WidgetRef ref, String sceneId) {
  ref.read(openContentIdProvider.notifier).state = sceneId;
  ref.read(openReferenceProvider.notifier).state = null;
}

/// Refreshes every list an owner's reference panels show. Call after any
/// write rather than invalidating providers ad hoc at each call site.
void invalidateReferences(WidgetRef ref, ContentOwner owner) {
  ref.invalidate(characterListProvider(owner));
  ref.invalidate(worldListProvider(owner));
  ref.invalidate(storyNoteListProvider(owner));
}

/// Moves [entry] from [from]'s storage to [to]'s storage — promoting a
/// project-level character/world entry to its series, or demoting a
/// series-level one back into a member project. The id, fields, and image
/// carry over unchanged (the `assets/images/<id>.ext` naming is the same
/// under any owner, so the image just needs copying, not re-attaching).
///
/// A moved character's Relationship Diagram edges and node position are
/// dropped rather than carried over — same as [ProfileService.delete] — the
/// diagram is project-scoped and a series has none to move them into.
Future<void> moveProfileEntry(
  WidgetRef ref, {
  required ContentOwner from,
  required ContentOwner to,
  required ProfileKind kind,
  required ProfileEntry entry,
}) async {
  final provider =
      kind == ProfileKind.character ? characterServiceProvider : worldServiceProvider;
  final sourceService = await ref.read(provider(from).future);
  final destService = await ref.read(provider(to).future);

  final imageSource = sourceService.imageFile(entry);
  if (imageSource != null && await imageSource.exists()) {
    final destImage = destService.imageFile(entry)!;
    await destImage.parent.create(recursive: true);
    await imageSource.copy(destImage.path);
  }
  await destService.save(entry);
  await sourceService.delete(entry);

  invalidateReferences(ref, from);
  invalidateReferences(ref, to);
}
