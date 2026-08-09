import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/content_owner.dart';
import '../models/manuscript.dart';
import '../models/profile_entry.dart';
import '../models/project.dart';
import '../services/app_logger.dart';
import '../services/manuscript_service.dart';
import '../state/drive_auto_sync_provider.dart';
import '../state/library_provider.dart';
import '../state/manuscript_provider.dart';
import '../state/reference_panel_provider.dart';
import '../state/reference_provider.dart';
import '../state/vault_provider.dart';
import '../widgets/editor_settings_dialog.dart';
import '../widgets/help_drawer.dart';
import '../widgets/manuscript_tree.dart';
import '../widgets/note_editor.dart';
import '../widgets/notes_panel.dart';
import '../widgets/profile_editor.dart';
import '../widgets/profile_panel.dart';
import '../widgets/quick_capture_dialog.dart';
import '../widgets/reference_panel.dart';
import '../widgets/resize_handle.dart';
import '../widgets/scene_editor.dart';
import '../widgets/todo_panel.dart';
import '../widgets/vault_unlock_dialog.dart';
import 'export_screen.dart';
import 'goals_screen.dart';
import 'plot_grid_screen.dart';
import 'relationship_screen.dart';
import 'review_export_screen.dart';
import 'series_detail_screen.dart';
import 'timeline_screen.dart';

/// How often the open project's vault is refreshed while writing. Frequent
/// enough that an unnoticed disaster loses at most half an hour, infrequent
/// enough that zipping and encrypting the project doesn't become a recurring
/// interruption.
const _autoBackupInterval = Duration(minutes: 30);

/// Below this width, the three-pane desktop layout (sidebar + editor +
/// reference panel, all docked side by side) stops fitting — on a phone-width
/// screen it leaves barely any room for the manuscript itself even when
/// nothing overflows outright. Chosen well above typical phone widths
/// (~360-430dp) and below typical desktop window widths, so phones/narrow
/// split-screen windows get the single-pane layout and normal desktop use is
/// unaffected.
const _kNarrowBreakpoint = 700.0;

/// The manuscript tree / characters / world / notes / to-dos tab group,
/// factored out so it can be hosted either inline in the docked sidebar
/// (wide/desktop layout) or inside a [Drawer] (narrow/phone layout) without
/// duplicating the tab setup. Watches its own providers rather than taking
/// already-resolved data, since the two call sites don't share a build
/// context that's convenient to thread that through.
class _ManuscriptSidebarTabs extends ConsumerWidget {
  const _ManuscriptSidebarTabs({required this.project});

  final Project project;

  /// Index-matched to the [TabBar]'s five tabs above — which help topic the
  /// header's help icon shows for whichever tab is currently selected.
  static const _sidebarTabHelpTopics = [
    'manuscript',
    'charactersWorld',
    'charactersWorld',
    'notes',
    'todos',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(manuscriptServiceProvider(project)).valueOrNull;
    final structure = ref
        .watch(manuscriptStructureProvider(project))
        .valueOrNull;
    if (service == null || structure == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          Row(
            children: [
              // Icons rather than text labels: five text tabs don't fit in a
              // 280px sidebar without truncating.
              const Expanded(
                child: TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.menu_book_outlined), height: 46),
                    Tab(icon: Icon(Icons.people_outline), height: 46),
                    Tab(icon: Icon(Icons.public), height: 46),
                    Tab(icon: Icon(Icons.sticky_note_2_outlined), height: 46),
                    Tab(icon: Icon(Icons.checklist), height: 46),
                  ],
                ),
              ),
              // One help icon that follows whichever tab is selected, rather
              // than five — the tab bar has no room to spare for a sixth
              // icon, and each tab already has its own topic in
              // help_content.dart (manuscript/charactersWorld/notes/todos).
              Builder(
                builder: (context) {
                  final controller = DefaultTabController.of(context);
                  return AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) => HelpIconButton(
                      topicId: _sidebarTabHelpTopics[controller.index],
                    ),
                  );
                },
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ManuscriptTree(
                  project: project,
                  service: service,
                  structure: structure,
                ),
                ProfilePanel(
                  owner: ContentOwner.project(project),
                  kind: ProfileKind.character,
                ),
                ProfilePanel(
                  owner: ContentOwner.project(project),
                  kind: ProfileKind.world,
                ),
                NotesPanel(owner: ContentOwner.project(project)),
                TodoPanel(owner: ContentOwner.project(project)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The open-project shell: manuscript tree + to-dos in a sidebar, the scene
/// editor as the main pane, and Focus Mode that collapses everything but the
/// prose.
class ProjectShellScreen extends ConsumerStatefulWidget {
  const ProjectShellScreen({super.key, required this.project});

  final Project project;

  @override
  ConsumerState<ProjectShellScreen> createState() => _ProjectShellScreenState();
}

class _ProjectShellScreenState extends ConsumerState<ProjectShellScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final VaultActions _vaultActions;
  Timer? _backupTimer;

  /// Mirrored from the provider during build so [dispose] doesn't have to read
  /// providers after the widget is unmounted.
  bool _autoBackupEnabled = true;

  @override
  void initState() {
    super.initState();
    _vaultActions = ref.read(vaultActionsProvider);
    _backupTimer = Timer.periodic(_autoBackupInterval, (_) => _autoBackup());
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptUnlock());
  }

  @override
  void dispose() {
    _backupTimer?.cancel();
    if (_autoBackupEnabled) {
      // Fire-and-forget: closing a project must not wait on (or fail because
      // of) a backup. refreshProject is a no-op when the vault is locked.
      _vaultActions.refreshProject(widget.project).catchError((
        Object error,
        StackTrace stack,
      ) {
        AppLogger.logError(error, stack, context: 'vault-backup-on-close');
        return null;
      });
    }
    super.dispose();
  }

  Future<void> _maybePromptUnlock() async {
    if (ref.read(unlockPromptDismissedProvider)) return;
    final status = await ref.read(vaultStatusProvider.future);
    if (status != VaultStatus.locked || !mounted) return;

    final unlocked = await showVaultUnlockDialog(context);
    if (!unlocked) {
      ref.read(unlockPromptDismissedProvider.notifier).state = true;
    }
  }

  Future<void> _renameProject() async {
    final project = widget.project;
    final controller = TextEditingController(text: project.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Not disposed here on purpose: the dialog's closing (pop) animation
    // still needs this TextField/controller for another frame after
    // showDialog's Future resolves — disposing it immediately, right here,
    // used to crash the app ("A TextEditingController was used after being
    // disposed", cascading into framework assertions during that
    // in-flight transition). Same pattern as `_promptForText` in
    // notes_panel.dart, which never disposes its dialog-scoped controller
    // either — a short-lived controller like this is cheap enough to just
    // let get garbage-collected once the dialog's Element is gone.
    if (newTitle == null || newTitle.isEmpty || newTitle == project.title) {
      return;
    }

    final library = ref.read(libraryServiceProvider);
    final updated = await library.renameProject(project, newTitle);
    ref.invalidate(projectListProvider);
    if (ref.read(currentProjectProvider)?.id == updated.id) {
      ref.read(currentProjectProvider.notifier).state = updated;
    }
  }

  /// Returns to the library, or — if this project was opened from inside a
  /// series (see `currentSeriesProvider`'s doc) — back to that series'
  /// screen instead. Clearing `currentProjectProvider` swaps `NarraityApp`'s
  /// `home` back to `LibraryScreen`; pushing `SeriesDetailScreen` on top of
  /// that (rather than skipping the swap) keeps the same pushed-route
  /// pattern `SeriesDetailScreen`'s own project-open handler relies on.
  void _goBack(BuildContext context, WidgetRef ref) {
    final series = ref.read(currentSeriesProvider);
    ref.read(currentSeriesProvider.notifier).state = null;
    // A project-level character/note left open here shouldn't carry into
    // the series screen, where that id wouldn't resolve to anything.
    ref.read(openReferenceProvider.notifier).state = null;
    ref.read(currentProjectProvider.notifier).state = null;
    if (series != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: series)),
      );
    }
  }

  Future<void> _autoBackup() async {
    if (!_autoBackupEnabled) return;
    try {
      await _vaultActions.refreshProject(widget.project);
      if (mounted) ref.invalidate(vaultGenerationsProvider(widget.project));
    } catch (error, stack) {
      AppLogger.logError(error, stack, context: 'vault-backup-periodic');
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    _autoBackupEnabled = ref.watch(vaultAutoRefreshProvider);
    // Active only while immediate-sync is enabled and Drive is connected
    // (see projectFileWatcherProvider) — watched here so it starts/stops
    // with this screen rather than needing its own always-mounted widget.
    ref.watch(projectFileWatcherProvider);
    final focusMode = ref.watch(focusModeProvider);
    final series = ref.watch(currentSeriesProvider);
    final reference = ref.watch(openReferenceProvider);
    final referenceVisible = ref.watch(referencePanelVisibleProvider);
    final serviceAsync = ref.watch(manuscriptServiceProvider(project));
    final structureAsync = ref.watch(manuscriptStructureProvider(project));
    final isNarrow = MediaQuery.sizeOf(context).width < _kNarrowBreakpoint;

    return Scaffold(
      key: _scaffoldKey,
      drawer: (!focusMode && isNarrow)
          ? Drawer(child: SafeArea(child: _ManuscriptSidebarTabs(project: project)))
          : null,
      appBar: focusMode
          ? null
          : AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: series == null
                    ? 'Back to Library'
                    : 'Back to "${series.title}"',
                onPressed: () => _goBack(context, ref),
              ),
              title: InkWell(
                onTap: _renameProject,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        project.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit_outlined, size: 16),
                  ],
                ),
              ),
              actions: [
                // Putting an Expanded/SingleChildScrollView directly inside
                // `actions` (an earlier attempt at this fix) is an
                // anti-pattern: AppBar's internal actions Row uses
                // `mainAxisSize: MainAxisSize.min`, which doesn't give an
                // Expanded child a well-defined Flex ancestor — it rendered
                // the drawer button on top of the leading back button
                // instead of after the title. Standard Material fix instead:
                // a few primary actions stay directly visible, everything
                // else moves behind one overflow (⋮) menu, so the action row
                // is always a small, fixed number of plain IconButtons no
                // matter how many actions this screen has.
                if (isNarrow)
                  IconButton(
                    tooltip: 'Manuscript / Characters / World / Notes / To-dos',
                    icon: const Icon(Icons.menu_book_outlined),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                IconButton(
                  tooltip: isNarrow
                      ? 'Reference Panel'
                      : (referenceVisible
                            ? 'Hide Reference Panel'
                            : 'Show Reference Panel'),
                  isSelected: !isNarrow && referenceVisible,
                  icon: const Icon(Icons.menu_open),
                  onPressed: () {
                    // Narrow layout has no room to dock the panel alongside
                    // the editor — push it full-screen instead, matching the
                    // drawer treatment given to the sidebar above.
                    if (isNarrow) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (routeContext) => Scaffold(
                            body: SafeArea(
                              child: ReferencePanel(
                                project: project,
                                onClose: () => Navigator.of(routeContext).pop(),
                              ),
                            ),
                          ),
                        ),
                      );
                    } else {
                      ref.read(referencePanelVisibleProvider.notifier).toggle();
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Focus Mode (Esc to exit)',
                  icon: const Icon(Icons.center_focus_strong),
                  onPressed: () =>
                      ref.read(focusModeProvider.notifier).state = true,
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (action) {
                    switch (action) {
                      case 'newIdea':
                        showQuickCaptureDialog(context, ref);
                      case 'goals':
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => GoalsScreen(project: project),
                          ),
                        );
                      case 'plotGrid':
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlotGridScreen(project: project),
                          ),
                        );
                      case 'timeline':
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TimelineScreen(project: project),
                          ),
                        );
                      case 'relationships':
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RelationshipScreen(project: project),
                          ),
                        );
                      case 'reviewExport':
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ReviewExportScreen(project: project),
                          ),
                        );
                      case 'export':
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ExportScreen(project: project),
                          ),
                        );
                      case 'editorSettings':
                        showEditorSettingsDialog(context, ref);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'newIdea', child: Text('New Idea')),
                    PopupMenuItem(value: 'goals', child: Text('Goals')),
                    PopupMenuItem(value: 'plotGrid', child: Text('Plot Grid')),
                    PopupMenuItem(value: 'timeline', child: Text('Timeline')),
                    PopupMenuItem(
                      value: 'relationships',
                      child: Text('Relationships'),
                    ),
                    PopupMenuItem(
                      value: 'reviewExport',
                      child: Text('Export / Import for Review'),
                    ),
                    PopupMenuItem(value: 'export', child: Text('Export')),
                    PopupMenuItem(
                      value: 'editorSettings',
                      child: Text('Editor settings'),
                    ),
                  ],
                ),
                const HelpIconButton(topicId: 'projectToolbar'),
                const SizedBox(width: 8),
              ],
            ),
      body: structureAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) =>
            Center(child: Text('Failed to load manuscript: $err')),
        data: (structure) {
          final service = serviceAsync.valueOrNull;
          if (service == null) {
            return const Center(child: CircularProgressIndicator());
          }

          // Default the editor to the first scene on open.
          final openId =
              ref.watch(openContentIdProvider) ??
              structure.allContentIds.firstOrNull;

          return _FocusModeEscape(
            enabled: focusMode,
            onExit: () => ref.read(focusModeProvider.notifier).state = false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The stored width is a fraction of the available width (see
                // ManuscriptSidebarWidthNotifier's doc comment), which looks
                // right on a wide desktop window but collapses to an
                // unreadably narrow sidebar on a phone-width screen — clamp
                // to a minimum absolute pixel width (but never more than half
                // the available space, so the main pane always has room too).
                final sidebarWidth = math.max(
                  constraints.maxWidth * ref.watch(manuscriptSidebarWidthProvider),
                  math.min(200.0, constraints.maxWidth * 0.5),
                );
                return Row(
                  children: [
                    // Narrow layout: sidebar lives in the Drawer (see the
                    // Scaffold's `drawer`) and the reference panel is a
                    // pushed full-screen route (see the AppBar action above)
                    // — neither is docked here, so the editor gets the full
                    // width instead of being squeezed into whatever's left
                    // over from two docked panels plus their resize handles.
                    if (!focusMode && !isNarrow) ...[
                      SizedBox(
                        width: sidebarWidth,
                        child: _ManuscriptSidebarTabs(project: project),
                      ),
                      ResizeHandle(
                        onDrag: (delta) => ref
                            .read(manuscriptSidebarWidthProvider.notifier)
                            .set(
                              ref.read(manuscriptSidebarWidthProvider) +
                                  delta / constraints.maxWidth,
                            ),
                        onDragEnd: () => ref
                            .read(manuscriptSidebarWidthProvider.notifier)
                            .save(),
                      ),
                    ],
                    Expanded(
                      child: _mainPane(
                        reference: reference,
                        openId: openId,
                        service: service,
                        structure: structure,
                      ),
                    ),
                    // Focus Mode hides the panel too — the point of Focus Mode is
                    // nothing but prose on screen.
                    if (!focusMode && !isNarrow && referenceVisible) ...[
                      ResizeHandle(
                        onDrag: (delta) => ref
                            .read(referencePanelWidthProvider.notifier)
                            .set(ref.read(referencePanelWidthProvider) - delta),
                        onDragEnd: () => ref
                            .read(referencePanelWidthProvider.notifier)
                            .save(),
                      ),
                      SizedBox(
                        width: ref.watch(referencePanelWidthProvider),
                        child: ReferencePanel(project: project),
                      ),
                    ],
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// An open reference entry takes over the main pane; otherwise the scene
  /// editor shows. The two selections are kept independently so closing a
  /// character returns you to the scene you were writing, not to nothing.
  Widget _mainPane({
    required ReferenceSelection? reference,
    required String? openId,
    required ManuscriptService service,
    required ManuscriptStructure structure,
  }) {
    final project = widget.project;

    if (reference != null) {
      final owner = ContentOwner.project(project);
      return switch (reference.kind) {
        ReferenceKind.character => ProfileEditor(
          owner: owner,
          kind: ProfileKind.character,
          entryId: reference.id,
        ),
        ReferenceKind.world => ProfileEditor(
          owner: owner,
          kind: ProfileKind.world,
          entryId: reference.id,
        ),
        ReferenceKind.note => NoteEditor(owner: owner, noteId: reference.id),
      };
    }

    if (openId == null) {
      return const Center(child: Text('Select a scene to start writing'));
    }
    return SceneEditor(
      project: project,
      service: service,
      contentId: openId,
      fallbackTitle: _titleFor(structure, openId),
    );
  }

  String _titleFor(ManuscriptStructure structure, String id) {
    for (final section in [...structure.frontMatter, ...structure.backMatter]) {
      if (section.id == id) return section.title;
    }
    String? search(List<ManuscriptNode> nodes) {
      for (final node in nodes) {
        if (node.id == id) return node.title;
        final found = search(node.children);
        if (found != null) return found;
      }
      return null;
    }

    return search(structure.nodes) ?? 'Untitled';
  }
}

// _ResizeHandle moved to widgets/resize_handle.dart (as public `ResizeHandle`)
// so series_detail_screen.dart's own sidebar could reuse it too.

/// Esc exits Focus Mode from anywhere in the shell. An ancestor [Focus] sees
/// key events bubbling up from whatever descendant (e.g. the editor's
/// TextField) currently has focus.
class _FocusModeEscape extends StatelessWidget {
  const _FocusModeEscape({
    required this.enabled,
    required this.onExit,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onExit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onExit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
