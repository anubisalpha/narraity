import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/content_owner.dart';
import '../models/profile_entry.dart';
import '../models/project.dart';
import '../models/series.dart';
import '../state/library_provider.dart';
import '../state/manuscript_provider.dart';
import '../state/reference_panel_provider.dart'
    show manuscriptSidebarWidthProvider;
import '../state/reference_provider.dart';
import '../widgets/help_drawer.dart';
import '../widgets/new_project_dialog.dart';
import '../widgets/note_editor.dart';
import '../widgets/notes_panel.dart';
import '../widgets/profile_editor.dart';
import '../widgets/profile_panel.dart';
import '../widgets/project_actions.dart';
import '../widgets/project_kind_style.dart';
import '../widgets/resize_handle.dart';
import '../widgets/todo_panel.dart';

/// A series' own screen: its projects (the default main-pane view), plus —
/// shared across every project inside it, unlike anything else in this app —
/// Characters, World, Notes, and To-dos in a resizable left sidebar that
/// mirrors the project shell's own. Pushed from the library's stacked
/// series card. Renaming/deleting the series, and adding a new project
/// directly into it, live here rather than on the library screen itself.
class SeriesDetailScreen extends ConsumerWidget {
  const SeriesDetailScreen({super.key, required this.series});

  final Series series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectListProvider);
    final reference = ref.watch(openReferenceProvider);
    final owner = ContentOwner.series(series);

    return Scaffold(
      appBar: AppBar(
        title: Text(series.title),
        actions: [
          PopupMenuButton<String>(
            onSelected: (action) async {
              switch (action) {
                case 'rename':
                  await _rename(context, ref);
                case 'delete':
                  await _delete(context, ref);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename Series')),
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete Series (keeps projects)'),
              ),
            ],
          ),
          const HelpIconButton(topicId: 'series'),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final sidebarWidth =
              constraints.maxWidth * ref.watch(manuscriptSidebarWidthProvider);
          return Row(
            children: [
              SizedBox(
                width: sidebarWidth,
                child: DefaultTabController(
                  length: 4,
                  child: Column(
                    children: [
                      // Icons rather than text labels: same reasoning as the
                      // project shell's own sidebar tabs (manuscript_tree.dart)
                      // — text doesn't fit a resizable sidebar at its
                      // narrowest without truncating.
                      const TabBar(
                        tabs: [
                          Tab(icon: Icon(Icons.people_outline), height: 46),
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
                            ProfilePanel(
                              owner: owner,
                              kind: ProfileKind.character,
                            ),
                            ProfilePanel(owner: owner, kind: ProfileKind.world),
                            NotesPanel(owner: owner),
                            TodoPanel(owner: owner),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ResizeHandle(
                onDrag: (delta) => ref
                    .read(manuscriptSidebarWidthProvider.notifier)
                    .set(
                      ref.read(manuscriptSidebarWidthProvider) +
                          delta / constraints.maxWidth,
                    ),
                onDragEnd: () =>
                    ref.read(manuscriptSidebarWidthProvider.notifier).save(),
              ),
              Expanded(
                child: reference != null
                    ? _ReferenceMainPane(owner: owner, reference: reference)
                    : projectsAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (err, stack) => Center(
                          child: Text('Failed to load projects: $err'),
                        ),
                        data: (allProjects) {
                          final projects = allProjects
                              .where((p) => p.seriesId == series.id)
                              .toList();
                          return projects.isEmpty
                              ? _EmptySeries(series: series)
                              : _SeriesProjectGrid(
                                  projects: projects,
                                  series: series,
                                );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: reference != null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addProject(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('New Project in Series'),
            ),
    );
  }

  Future<void> _addProject(BuildContext context, WidgetRef ref) async {
    final result = await showNewProjectDialog(context);
    if (result == null) return;

    final service = ref.read(libraryServiceProvider);
    await service.createProject(
      title: result.title,
      author: result.author,
      seriesId: series.id,
    );
    // The importer/manuscript seed step (see LibraryScreen._createProject)
    // is deliberately skipped here in favor of the simpler default seed —
    // opening the project from this grid still lands on a normal, usable
    // manuscript; picking a different starting structure can be done the
    // same way any project's structure is changed later.
    ref.invalidate(projectListProvider);
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: series.title);
    final formKey = GlobalKey<FormState>();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Series'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Title is required'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(context).pop(controller.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (title == null) return;

    final service = ref.read(seriesServiceProvider);
    await service.renameSeries(series, title);
    ref.invalidate(seriesListProvider);
    if (context.mounted) {
      Navigator.of(
        context,
      ).pop(); // back to library; its title is now stale otherwise
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this series?'),
        content: const Text(
          'The series grouping is removed, but every project inside it is kept — '
          'they\'ll appear as standalone projects in your library again. Any '
          'series-level characters, worldbuilding, notes, or to-dos are '
          'removed with it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete Series'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final service = ref.read(seriesServiceProvider);
    await service.deleteSeries(series);
    ref.invalidate(seriesListProvider);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

/// Wraps [ProfileEditor]/[NoteEditor] with a way back to the project grid —
/// the project shell doesn't need this (closing a reference there means
/// switching to a scene instead), but a series screen has no scene to fall
/// back to.
class _ReferenceMainPane extends ConsumerWidget {
  const _ReferenceMainPane({required this.owner, required this.reference});

  final ContentOwner owner;
  final ReferenceSelection reference;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: TextButton.icon(
            onPressed: () =>
                ref.read(openReferenceProvider.notifier).state = null,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back to Projects'),
          ),
        ),
        Expanded(
          child: switch (reference.kind) {
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
            ReferenceKind.note => NoteEditor(
              owner: owner,
              noteId: reference.id,
            ),
          },
        ),
      ],
    );
  }
}

class _EmptySeries extends StatelessWidget {
  const _EmptySeries({required this.series});

  final Series series;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.collections_bookmark_outlined,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'No projects in "${series.title}" yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text('Add one with the button below.'),
        ],
      ),
    );
  }
}

class _SeriesProjectGrid extends ConsumerWidget {
  const _SeriesProjectGrid({required this.projects, required this.series});

  final List<Project> projects;
  final Series series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Same rule as the top-level library grid (see _LibraryGrid in
    // library_screen.dart): drag-and-drop-ordered projects sort first (by
    // their explicit position), everything else falls in after by recency.
    // sortOrder here is scoped to "position within this series" — a
    // standalone project's sortOrder (from the top-level grid) is a
    // separate numbering, never shown together with these.
    final ordered = List<Project>.from(projects)
      ..sort((a, b) {
        final aOrder = a.sortOrder;
        final bOrder = b.sortOrder;
        if (aOrder != null && bOrder != null) return aOrder.compareTo(bOrder);
        if (aOrder != null) return -1;
        if (bOrder != null) return 1;
        return b.modified.compareTo(a.modified);
      });

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: 160,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: ordered.length,
      itemBuilder: (context, index) {
        final project = ordered[index];
        final card = ProjectKindFrame(
          kind: project.kind,
          child: Card(
            child: InkWell(
              onTap: () {
                ref.read(openContentIdProvider.notifier).state = null;
                // Remembered so the project shell's back button can return
                // here instead of the top-level library — see
                // currentSeriesProvider's doc in library_provider.dart.
                ref.read(currentSeriesProvider.notifier).state = series;
                // Don't let a series-level character/note left open here
                // carry into the project shell, where that id wouldn't
                // resolve to anything.
                ref.read(openReferenceProvider.notifier).state = null;
                ref.read(currentProjectProvider.notifier).state = project;
                // Setting currentProjectProvider swaps NarraityApp's `home`
                // widget from LibraryScreen to ProjectShellScreen (see
                // app.dart), but that swap happens underneath this screen,
                // which is a *pushed* route sitting on top of `home` in the
                // Navigator stack — so without popping back to the root, the
                // rebuild is invisible and the project never appears to open.
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          ProjectKindStyle.of(project.kind).icon,
                          color: ProjectKindStyle.of(
                            project.kind,
                          ).accent(Theme.of(context).colorScheme),
                        ),
                        const Spacer(),
                        PopupMenuButton<String>(
                          tooltip: 'Project options',
                          onSelected: (action) async {
                            switch (action) {
                              case 'remove':
                                final library = ref.read(
                                  libraryServiceProvider,
                                );
                                await library.saveProject(
                                  project.copyWith(clearSeriesId: true),
                                );
                                ref.invalidate(projectListProvider);
                              case 'style':
                                await editProjectCardStyle(
                                  context,
                                  ref,
                                  project,
                                );
                              case 'archive':
                                await archiveProjectWithConfirmation(
                                  context,
                                  ref,
                                  project,
                                );
                              case 'delete':
                                await deleteProjectWithConfirmation(
                                  context,
                                  ref,
                                  project,
                                );
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'remove',
                              child: Text('Remove from Series'),
                            ),
                            PopupMenuItem(
                              value: 'style',
                              child: Text('Card style…'),
                            ),
                            PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'archive',
                              child: Text('Archive'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Text(
                      project.title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (project.author != null)
                      Text(
                        project.author!,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const Spacer(),
                    Text(
                      'Modified ${DateFormat.yMMMd().format(project.modified)}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        return DragTarget<int>(
          onWillAcceptWithDetails: (details) => details.data != index,
          onAcceptWithDetails: (details) =>
              _reorder(ref, ordered, details.data, index),
          builder: (context, candidateData, rejectedData) => Draggable<int>(
            data: index,
            feedback: Opacity(
              opacity: 0.8,
              child: SizedBox(
                width: 220,
                height: 160,
                child: Material(child: card),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.3, child: card),
            child: candidateData.isNotEmpty
                ? Opacity(opacity: 0.5, child: card)
                : card,
          ),
        );
      },
    );
  }

  /// Reassigns sequential `sortOrder` (0..n-1) among this series' own
  /// projects only — mirrors `_LibraryGrid._reorder` in library_screen.dart,
  /// but scoped to [projects] instead of the whole mixed library grid.
  Future<void> _reorder(
    WidgetRef ref,
    List<Project> ordered,
    int movedIndex,
    int targetIndex,
  ) async {
    final reordered = List<Project>.from(ordered);
    final moved = reordered.removeAt(movedIndex);
    reordered.insert(targetIndex, moved);

    final libraryService = ref.read(libraryServiceProvider);
    for (var i = 0; i < reordered.length; i++) {
      final project = reordered[i];
      if (project.sortOrder == i) continue;
      await libraryService.saveProject(project.copyWith(sortOrder: i));
    }

    ref.invalidate(projectListProvider);
  }
}
