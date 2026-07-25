import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/profile_entry.dart';
import '../models/project.dart';
import 'reference_provider.dart';

/// State for the Reference Panel (PLAN.md "Feature: Reference Panel"): what's
/// pinned, what the open scene mentions, and the panel's own visibility and
/// width.

/// Whether the docked panel is shown. Persisted so a writer who works with it
/// closed doesn't have to close it every session.
class ReferencePanelVisibleNotifier extends Notifier<bool> {
  static const _prefKey = 'referencePanel.visible';

  @override
  bool build() {
    _restore();
    return true;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_prefKey) ?? true;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, state);
  }
}

final referencePanelVisibleProvider =
    NotifierProvider<ReferencePanelVisibleNotifier, bool>(
        ReferencePanelVisibleNotifier.new);

class ReferencePanelWidthNotifier extends Notifier<double> {
  static const _prefKey = 'referencePanel.width';
  static const defaultWidth = 300.0;
  static const minWidth = 220.0;
  static const maxWidth = 480.0;

  @override
  double build() {
    _restore();
    return defaultWidth;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = (prefs.getDouble(_prefKey) ?? defaultWidth).clamp(minWidth, maxWidth);
  }

  /// Live value during a drag — not persisted per pixel; call [save] on drag
  /// end so the preference file isn't rewritten continuously.
  void set(double width) => state = width.clamp(minWidth, maxWidth);

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefKey, state);
  }
}

final referencePanelWidthProvider =
    NotifierProvider<ReferencePanelWidthNotifier, double>(
        ReferencePanelWidthNotifier.new);

/// Entry ids pinned to the panel for one project — "keep this visible no
/// matter what scene I'm in". Persisted per project (keyed by project id, not
/// folder name, which can change on rename) but in app preferences rather
/// than the project folder: pins are this machine's workspace state, not part
/// of the manuscript, and shouldn't ride along in vaults or Drive sync.
class PinnedReferencesNotifier extends FamilyNotifier<List<String>, Project> {
  String get _prefKey => 'referencePanel.pins.${arg.id}';

  @override
  List<String> build(Project project) {
    _restore();
    return const [];
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getStringList(_prefKey) ?? const [];
  }

  Future<void> toggle(String entryId) async {
    state = state.contains(entryId)
        ? state.where((id) => id != entryId).toList()
        : [...state, entryId];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKey, state);
  }
}

final pinnedReferencesProvider =
    NotifierProvider.family<PinnedReferencesNotifier, List<String>, Project>(
        PinnedReferencesNotifier.new);

/// Names mentioned (`[[Name]]`) in the scene currently open in the editor,
/// published by SceneEditor on its save debounce. One open scene at a time,
/// so this isn't project-keyed.
final sceneMentionedNamesProvider = StateProvider<List<String>>((ref) => const []);

/// The panel's resolved content: mentioned names matched against real entries
/// (characters first, then world), plus the names that matched nothing.
class ResolvedMentions {
  const ResolvedMentions(this.entries, this.unresolved);

  final List<ProfileEntry> entries;
  final List<String> unresolved;
}

/// Pure so it's directly testable: matching is case-insensitive on the whole
/// trimmed name, characters win a name collision with world entries, and
/// order follows the mention order in the scene.
ResolvedMentions resolveMentions(
  List<String> names,
  List<ProfileEntry> characters,
  List<ProfileEntry> world,
) {
  ProfileEntry? findIn(List<ProfileEntry> entries, String lower) {
    for (final entry in entries) {
      if (entry.name.trim().toLowerCase() == lower) return entry;
    }
    return null;
  }

  final resolved = <ProfileEntry>[];
  final unresolved = <String>[];
  for (final name in names) {
    final lower = name.trim().toLowerCase();
    final entry = findIn(characters, lower) ?? findIn(world, lower);
    if (entry != null) {
      resolved.add(entry);
    } else {
      unresolved.add(name);
    }
  }
  return ResolvedMentions(resolved, unresolved);
}

/// Everything the panel shows for [project]: pinned entries (all of them,
/// regardless of scene), then entries mentioned in the open scene that aren't
/// already pinned, then unresolved mention names.
class ReferencePanelContent {
  const ReferencePanelContent({
    required this.pinned,
    required this.mentioned,
    required this.unresolved,
  });

  final List<ProfileEntry> pinned;
  final List<ProfileEntry> mentioned;
  final List<String> unresolved;

  bool get isEmpty => pinned.isEmpty && mentioned.isEmpty && unresolved.isEmpty;
}

final referencePanelContentProvider =
    FutureProvider.family<ReferencePanelContent, Project>((ref, project) async {
  final characters = await ref.watch(characterListProvider(project).future);
  final world = await ref.watch(worldListProvider(project).future);
  final pinnedIds = ref.watch(pinnedReferencesProvider(project));
  final mentionedNames = ref.watch(sceneMentionedNamesProvider);

  final byId = {for (final entry in [...characters, ...world]) entry.id: entry};
  // Preserve pin order; silently drop ids whose entry has been deleted.
  final pinned = [
    for (final id in pinnedIds)
      if (byId.containsKey(id)) byId[id]!,
  ];

  final mentions = resolveMentions(mentionedNames, characters, world);
  final pinnedIdSet = pinned.map((e) => e.id).toSet();
  final mentioned =
      mentions.entries.where((e) => !pinnedIdSet.contains(e.id)).toList();

  return ReferencePanelContent(
    pinned: pinned,
    mentioned: mentioned,
    unresolved: mentions.unresolved,
  );
});
