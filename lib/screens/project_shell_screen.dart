import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../widgets/manuscript_tree.dart';
import '../widgets/note_editor.dart';
import '../widgets/notes_panel.dart';
import '../widgets/profile_editor.dart';
import '../widgets/profile_panel.dart';
import '../widgets/quick_capture_dialog.dart';
import '../widgets/reference_panel.dart';
import '../widgets/scene_editor.dart';
import '../widgets/todo_panel.dart';
import '../widgets/vault_unlock_dialog.dart';
import 'export_screen.dart';
import 'goals_screen.dart';
import 'plot_grid_screen.dart';
import 'relationship_screen.dart';
import 'review_export_screen.dart';
import 'timeline_screen.dart';

/// How often the open project's vault is refreshed while writing. Frequent
/// enough that an unnoticed disaster loses at most half an hour, infrequent
/// enough that zipping and encrypting the project doesn't become a recurring
/// interruption.
const _autoBackupInterval = Duration(minutes: 30);

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
    final reference = ref.watch(openReferenceProvider);
    final referenceVisible = ref.watch(referencePanelVisibleProvider);
    final serviceAsync = ref.watch(manuscriptServiceProvider(project));
    final structureAsync = ref.watch(manuscriptStructureProvider(project));

    return Scaffold(
      appBar: focusMode
          ? null
          : AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Library',
                onPressed: () =>
                    ref.read(currentProjectProvider.notifier).state = null,
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
                IconButton(
                  tooltip: 'New Idea',
                  icon: const Icon(Icons.lightbulb_outline),
                  onPressed: () => showQuickCaptureDialog(context, ref),
                ),
                IconButton(
                  tooltip: 'Goals',
                  icon: const Icon(Icons.flag_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GoalsScreen(project: project),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Plot Grid',
                  icon: const Icon(Icons.grid_on_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlotGridScreen(project: project),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Timeline',
                  icon: const Icon(Icons.timeline),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TimelineScreen(project: project),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Relationships',
                  icon: const Icon(Icons.hub_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RelationshipScreen(project: project),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Export / Import for Review',
                  icon: const Icon(Icons.rate_review_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReviewExportScreen(project: project),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Export',
                  icon: const Icon(Icons.ios_share),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ExportScreen(project: project),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Editor settings',
                  icon: const Icon(Icons.text_fields),
                  onPressed: () => showEditorSettingsDialog(context, ref),
                ),
                IconButton(
                  tooltip: referenceVisible
                      ? 'Hide Reference Panel'
                      : 'Show Reference Panel',
                  isSelected: referenceVisible,
                  icon: const Icon(Icons.menu_open),
                  onPressed: () =>
                      ref.read(referencePanelVisibleProvider.notifier).toggle(),
                ),
                IconButton(
                  tooltip: 'Focus Mode (Esc to exit)',
                  icon: const Icon(Icons.center_focus_strong),
                  onPressed: () =>
                      ref.read(focusModeProvider.notifier).state = true,
                ),
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
                final sidebarWidth =
                    constraints.maxWidth *
                    ref.watch(manuscriptSidebarWidthProvider);
                return Row(
                  children: [
                    if (!focusMode)
                      SizedBox(
                        width: sidebarWidth,
                        child: DefaultTabController(
                          length: 5,
                          child: Column(
                            children: [
                              // Icons rather than text labels: five text tabs
                              // don't fit in a 280px sidebar without truncating.
                              const TabBar(
                                tabs: [
                                  Tab(
                                    icon: Icon(Icons.menu_book_outlined),
                                    height: 46,
                                  ),
                                  Tab(
                                    icon: Icon(Icons.people_outline),
                                    height: 46,
                                  ),
                                  Tab(icon: Icon(Icons.public), height: 46),
                                  Tab(
                                    icon: Icon(Icons.sticky_note_2_outlined),
                                    height: 46,
                                  ),
                                  Tab(icon: Icon(Icons.checklist), height: 46),
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
                                      project: project,
                                      kind: ProfileKind.character,
                                    ),
                                    ProfilePanel(
                                      project: project,
                                      kind: ProfileKind.world,
                                    ),
                                    NotesPanel(project: project),
                                    TodoPanel(project: project),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!focusMode)
                      _ResizeHandle(
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
                    if (!focusMode && referenceVisible) ...[
                      _ResizeHandle(
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
      return switch (reference.kind) {
        ReferenceKind.character => ProfileEditor(
          project: project,
          kind: ProfileKind.character,
          entryId: reference.id,
        ),
        ReferenceKind.world => ProfileEditor(
          project: project,
          kind: ProfileKind.world,
          entryId: reference.id,
        ),
        ReferenceKind.note => NoteEditor(
          project: project,
          noteId: reference.id,
        ),
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

/// Thin draggable divider that resizes an adjacent panel — the manuscript
/// sidebar on the left and the Reference Panel on the right both use this,
/// each translating the raw drag delta to its own width/fraction change
/// (and sign: the Reference Panel widens when dragged left, so its caller
/// inverts the delta).
class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDrag, required this.onDragEnd});

  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        onHorizontalDragEnd: (_) => onDragEnd(),
        // The visible divider is 1px, but the grab area is padded out to 8px:
        // a 1px drag target is painful to hit.
        child: const SizedBox(
          width: 8,
          child: Center(child: VerticalDivider(width: 1)),
        ),
      ),
    );
  }
}

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
