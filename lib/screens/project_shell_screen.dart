import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/manuscript.dart';
import '../models/project.dart';
import '../state/library_provider.dart';
import '../state/manuscript_provider.dart';
import '../widgets/editor_settings_dialog.dart';
import '../widgets/manuscript_tree.dart';
import '../widgets/quick_capture_dialog.dart';
import '../widgets/scene_editor.dart';
import '../widgets/todo_panel.dart';
import 'goals_screen.dart';

/// The open-project shell: manuscript tree + to-dos in a sidebar, the scene
/// editor as the main pane, and Focus Mode that collapses everything but the
/// prose.
class ProjectShellScreen extends ConsumerWidget {
  const ProjectShellScreen({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focusMode = ref.watch(focusModeProvider);
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
              title: Text(project.title),
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
                    MaterialPageRoute(builder: (_) => GoalsScreen(project: project)),
                  ),
                ),
                IconButton(
                  tooltip: 'Editor settings',
                  icon: const Icon(Icons.text_fields),
                  onPressed: () => showEditorSettingsDialog(context, ref),
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
          final openId = ref.watch(openContentIdProvider) ??
              structure.allContentIds.firstOrNull;

          return _FocusModeEscape(
            enabled: focusMode,
            onExit: () => ref.read(focusModeProvider.notifier).state = false,
            child: Row(
              children: [
                if (!focusMode)
                  SizedBox(
                    width: 280,
                    child: DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          const TabBar(tabs: [
                            Tab(text: 'Manuscript'),
                            Tab(text: 'To-dos'),
                          ]),
                          Expanded(
                            child: TabBarView(
                              children: [
                                ManuscriptTree(
                                  project: project,
                                  service: service,
                                  structure: structure,
                                ),
                                TodoPanel(project: project),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (!focusMode) const VerticalDivider(width: 1),
                Expanded(
                  child: openId == null
                      ? const Center(child: Text('Select a scene to start writing'))
                      : SceneEditor(
                          project: project,
                          service: service,
                          contentId: openId,
                          fallbackTitle: _titleFor(structure, openId),
                        ),
                ),
              ],
            ),
          );
        },
      ),
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
