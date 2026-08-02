import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/content_owner.dart';
import '../models/profile_entry.dart';
import '../models/project.dart';
import '../models/series.dart';
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
      ReferencePanelVisibleNotifier.new,
    );

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
    state = (prefs.getDouble(_prefKey) ?? defaultWidth).clamp(
      minWidth,
      maxWidth,
    );
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
      ReferencePanelWidthNotifier.new,
    );

/// Width of the project shell's left sidebar (manuscript tree / profiles /
/// world / notes / to-dos tabs), stored as a *fraction* of the shell's
/// available width rather than a fixed pixel count — unlike
/// [ReferencePanelWidthNotifier]. A fixed-pixel sidebar looks proportionally
/// wrong the moment the window is resized or reopened on a different
/// monitor; a fraction stays visually consistent across both, at the cost of
/// [minFraction]/[maxFraction] being the only clamp available here — the
/// caller (`project_shell_screen.dart`'s `LayoutBuilder`) is what turns this
/// back into a pixel width against the *current* available width.
class ManuscriptSidebarWidthNotifier extends Notifier<double> {
  static const _prefKey = 'projectShell.sidebarWidthFraction';
  static const defaultFraction = 0.2;
  static const minFraction = 0.12;
  static const maxFraction = 0.4;

  @override
  double build() {
    _restore();
    return defaultFraction;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = (prefs.getDouble(_prefKey) ?? defaultFraction).clamp(
      minFraction,
      maxFraction,
    );
  }

  /// Live value during a drag — not persisted per pixel; call [save] on drag
  /// end so the preference file isn't rewritten continuously.
  void set(double fraction) => state = fraction.clamp(minFraction, maxFraction);

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefKey, state);
  }
}

final manuscriptSidebarWidthProvider =
    NotifierProvider<ManuscriptSidebarWidthNotifier, double>(
      ManuscriptSidebarWidthNotifier.new,
    );

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
      PinnedReferencesNotifier.new,
    );

/// Entry ids pinned to the panel for one series — keyed by the series
/// itself, not by project, so a character pinned from the series' own
/// Characters tab shows up in the Reference Panel of *every* project inside
/// that series, not just the one open when it was pinned.
class PinnedSeriesReferencesNotifier extends FamilyNotifier<List<String>, Series> {
  String get _prefKey => 'referencePanel.seriesPins.${arg.id}';

  @override
  List<String> build(Series series) {
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

final pinnedSeriesReferencesProvider = NotifierProvider.family<
    PinnedSeriesReferencesNotifier, List<String>, Series>(
  PinnedSeriesReferencesNotifier.new,
);

/// Whether [entryId] is pinned for [owner] — dispatches to the project- or
/// series-keyed pin list depending on which kind of owner it is, so callers
/// (the Reference Panel's cards, `ProfilePanel`'s pin toggle) don't need to
/// know which provider backs which owner type.
bool isReferencePinned(WidgetRef ref, ContentOwner owner, String entryId) {
  final project = owner.projectOrNull;
  if (project != null) {
    return ref.watch(pinnedReferencesProvider(project)).contains(entryId);
  }
  final series = owner.seriesOrNull;
  if (series != null) {
    return ref.watch(pinnedSeriesReferencesProvider(series)).contains(entryId);
  }
  return false;
}

void toggleReferencePin(WidgetRef ref, ContentOwner owner, String entryId) {
  final project = owner.projectOrNull;
  if (project != null) {
    ref.read(pinnedReferencesProvider(project).notifier).toggle(entryId);
    return;
  }
  final series = owner.seriesOrNull;
  if (series != null) {
    ref.read(pinnedSeriesReferencesProvider(series).notifier).toggle(entryId);
  }
}

/// Names mentioned (`[[Name]]`) in the scene currently open in the editor,
/// published by SceneEditor on its save debounce. One open scene at a time,
/// so this isn't project-keyed.
final sceneMentionedNamesProvider = StateProvider<List<String>>(
  (ref) => const [],
);

/// The panel's resolved content: mentioned names matched against real entries
/// (characters first, then world), plus the names that matched nothing.
class ResolvedMentions {
  const ResolvedMentions(this.entries, this.unresolved);

  final List<ReferenceCardItem> entries;
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

  final resolved = <ReferenceCardItem>[];
  final unresolved = <String>[];
  for (final name in names) {
    final lower = name.trim().toLowerCase();
    final character = findIn(characters, lower);
    if (character != null) {
      resolved.add(ReferenceCardItem(character, ProfileKind.character));
      continue;
    }
    final worldEntry = findIn(world, lower);
    if (worldEntry != null) {
      resolved.add(ReferenceCardItem(worldEntry, ProfileKind.world));
    } else {
      unresolved.add(name);
    }
  }
  return ResolvedMentions(resolved, unresolved);
}

/// An entry plus which collection it came from. The kind travels with the
/// entry rather than being inferred from its id prefix: the panel has to know
/// which service to save an inline edit through, and guessing from the id
/// would write a hand-edited character into the worldbuilding folder — the
/// project invites hand-editing files, so ids can't be trusted to encode type.
class ReferenceCardItem {
  const ReferenceCardItem(this.entry, this.kind);

  final ProfileEntry entry;
  final ProfileKind kind;
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

  final List<ReferenceCardItem> pinned;
  final List<ReferenceCardItem> mentioned;
  final List<String> unresolved;

  bool get isEmpty => pinned.isEmpty && mentioned.isEmpty && unresolved.isEmpty;
}

final referencePanelContentProvider =
    FutureProvider.family<ReferencePanelContent, Project>((ref, project) async {
      final owner = ContentOwner.project(project);
      final characters = await ref.watch(characterListProvider(owner).future);
      final world = await ref.watch(worldListProvider(owner).future);
      final pinnedIds = ref.watch(pinnedReferencesProvider(project));
      final mentionedNames = ref.watch(sceneMentionedNamesProvider);

      final byId = {
        for (final entry in characters)
          entry.id: ReferenceCardItem(entry, ProfileKind.character),
        for (final entry in world)
          entry.id: ReferenceCardItem(entry, ProfileKind.world),
      };
      // Preserve pin order; silently drop ids whose entry has been deleted.
      final pinned = [
        for (final id in pinnedIds)
          if (byId.containsKey(id)) byId[id]!,
      ];

      final mentions = resolveMentions(mentionedNames, characters, world);
      final pinnedIdSet = pinned.map((item) => item.entry.id).toSet();
      final mentioned = mentions.entries
          .where((item) => !pinnedIdSet.contains(item.entry.id))
          .toList();

      return ReferencePanelContent(
        pinned: pinned,
        mentioned: mentioned,
        unresolved: mentions.unresolved,
      );
    });

/// The Reference Panel's "Series" tab content for [series] — same shape as
/// [referencePanelContentProvider], but reading the series' own characters
/// and worldbuilding, pinned via [pinnedSeriesReferencesProvider]. Keyed
/// only by series (not by which project is open), so it's identical no
/// matter which of the series' projects the panel is showing it from — the
/// whole point being that a series-level pin follows you between books.
/// Mentions still resolve against the scene currently open in *whichever*
/// project you're writing, so `[[Name]]` can reach a series-level character
/// without it being pinned first.
final seriesReferencePanelContentProvider =
    FutureProvider.family<ReferencePanelContent, Series>((ref, series) async {
      final owner = ContentOwner.series(series);
      final characters = await ref.watch(characterListProvider(owner).future);
      final world = await ref.watch(worldListProvider(owner).future);
      final pinnedIds = ref.watch(pinnedSeriesReferencesProvider(series));
      final mentionedNames = ref.watch(sceneMentionedNamesProvider);

      final byId = {
        for (final entry in characters)
          entry.id: ReferenceCardItem(entry, ProfileKind.character),
        for (final entry in world)
          entry.id: ReferenceCardItem(entry, ProfileKind.world),
      };
      final pinned = [
        for (final id in pinnedIds)
          if (byId.containsKey(id)) byId[id]!,
      ];

      final mentions = resolveMentions(mentionedNames, characters, world);
      final pinnedIdSet = pinned.map((item) => item.entry.id).toSet();
      final mentioned = mentions.entries
          .where((item) => !pinnedIdSet.contains(item.entry.id))
          .toList();

      return ReferencePanelContent(
        pinned: pinned,
        mentioned: mentioned,
        unresolved: mentions.unresolved,
      );
    });
