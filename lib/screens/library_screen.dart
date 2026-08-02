import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../models/manuscript_import.dart';
import '../models/project.dart';
import '../models/series.dart';
import '../services/import/manuscript_importer.dart';
import '../services/manuscript_service.dart';
import '../state/library_background_provider.dart';
import '../state/library_provider.dart';
import '../state/manuscript_provider.dart';
import '../state/reference_provider.dart';
import '../widgets/app_wordmark.dart';
import '../widgets/help_drawer.dart';
import '../widgets/project_actions.dart';
import '../widgets/import_destination_dialog.dart';
import '../widgets/move_to_series_dialog.dart';
import '../widgets/new_project_dialog.dart';
import '../widgets/new_series_dialog.dart';
import '../widgets/project_kind_style.dart';
import '../widgets/quick_capture_dialog.dart';
import '../widgets/update_available_banner.dart';
import '../widgets/whats_new_dialog.dart';
import 'app_goals_screen.dart';
import 'archived_projects_screen.dart';
import 'ideas_screen.dart';
import 'news_screen.dart';
import 'review_sessions_screen.dart';
import 'series_detail_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectListProvider);
    final seriesAsync = ref.watch(seriesListProvider);
    final background = ref.watch(libraryBackgroundProvider);

    return Scaffold(
      appBar: AppBar(
        title: const AppWordmark(),
        actions: [
          IconButton(
            tooltip: 'New Idea',
            icon: const Icon(Icons.lightbulb_outline),
            onPressed: () => showQuickCaptureDialog(context, ref),
          ),
          IconButton(
            tooltip: 'Global Ideas',
            icon: const Icon(Icons.tips_and_updates_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const IdeasScreen())),
          ),
          IconButton(
            tooltip: 'App-Wide Goals',
            icon: const Icon(Icons.flag_circle_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AppGoalsScreen())),
          ),
          IconButton(
            tooltip: 'Review a Manuscript',
            icon: const Icon(Icons.rate_review_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReviewSessionsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Import Manuscript',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: () => _importManuscript(context, ref),
          ),
          IconButton(
            tooltip: 'News',
            icon: const Icon(Icons.campaign_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const NewsScreen())),
          ),
          IconButton(
            tooltip: 'Archived & Deleted Projects',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ArchivedProjectsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          const HelpIconButton(topicId: 'library'),
          const SizedBox(width: 8),
        ],
      ),
      // The custom background (if any) wraps just the body content, not the
      // AppBar — an extra option alongside the theme selector (see
      // Settings > Appearance), not a replacement for it, so the app bar
      // keeps its normal themed look regardless of this choice.
      body: Container(
        decoration: background.decorationFor(context),
        child: Column(
          children: [
            const WhatsNewDialogTrigger(),
            const UpdateAvailableBanner(),
            Expanded(
              child: projectsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) =>
                    Center(child: Text('Failed to load library: $err')),
                data: (projects) => seriesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (err, stack) =>
                      Center(child: Text('Failed to load library: $err')),
                  data: (series) => (projects.isEmpty && series.isEmpty)
                      ? _EmptyLibrary(
                          onCreate: () => _createProject(context, ref),
                        )
                      : _LibraryGrid(projects: projects, series: series),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'newSeries',
            onPressed: () => _createSeries(context, ref),
            icon: const Icon(Icons.collections_bookmark_outlined),
            label: const Text('New Series'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'newProject',
            onPressed: () => _createProject(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('New Project'),
          ),
        ],
      ),
    );
  }

  Future<void> _createSeries(BuildContext context, WidgetRef ref) async {
    final title = await showNewSeriesDialog(context);
    if (title == null) return;

    final service = ref.read(seriesServiceProvider);
    await service.createSeries(title: title);
    ref.invalidate(seriesListProvider);
  }

  Future<void> _createProject(BuildContext context, WidgetRef ref) async {
    final result = await showNewProjectDialog(context);
    if (result == null) return;

    final service = ref.read(libraryServiceProvider);
    final project = await service.createProject(
      title: result.title,
      author: result.author,
      kind: result.kind,
    );

    // Seed the manuscript with the chosen starting structure right away —
    // loadStructure() only auto-seeds (with the Act>Chapter>Scene default)
    // if nothing exists yet, so doing it here explicitly is what makes the
    // structure picker actually take effect.
    final root = await service.libraryRoot();
    final manuscriptService = ManuscriptService(
      Directory(p.join(root.path, project.folderName)),
    );
    await manuscriptService.loadStructure(seed: result.seed);

    ref.invalidate(projectListProvider);
    ref.read(openContentIdProvider.notifier).state = null;
    ref.read(currentSeriesProvider.notifier).state = null;
    ref.read(openReferenceProvider.notifier).state = null;
    ref.read(currentProjectProvider.notifier).state = project;
  }

  Future<void> _importManuscript(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Import a manuscript (.docx, .txt, .md)',
      type: FileType.custom,
      allowedExtensions: supportedImportExtensions,
      lockParentWindow: true,
    );
    final path = result?.files.single.path;
    if (path == null) return;

    final importer = ManuscriptImporter();
    final List<ImportedNode> imported;
    try {
      imported = await importer.parseFile(path);
    } catch (error) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Could not import that file'),
          content: Text('$error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (!context.mounted) return;
    final libraryService = ref.read(libraryServiceProvider);
    final existingProjects = await libraryService.listProjects();

    if (!context.mounted) return;
    final destination = await showImportDestinationDialog(
      context,
      existingProjects: existingProjects,
      suggestedTitle: importer.suggestedTitle(path, imported),
    );
    if (destination == null) return;

    switch (destination) {
      case ImportAsNewProject(:final title, :final author):
        final project = await libraryService.createProject(
          title: title,
          author: author,
        );
        final root = await libraryService.libraryRoot();
        final service = ManuscriptService(
          Directory(p.join(root.path, project.folderName)),
        );
        await importer.materializeInto(service, imported);

        ref.invalidate(projectListProvider);
        ref.read(openContentIdProvider.notifier).state = null;
        ref.read(currentSeriesProvider.notifier).state = null;
        ref.read(openReferenceProvider.notifier).state = null;
        ref.read(currentProjectProvider.notifier).state = project;

      case ImportReplacingProject(:final project):
        if (!context.mounted) return;
        final confirmed = await _confirmReplace(context, project);
        if (!confirmed) return;

        final root = await libraryService.libraryRoot();
        final service = ManuscriptService(
          Directory(p.join(root.path, project.folderName)),
        );
        await importer.clearExistingManuscript(service);
        await importer.materializeInto(service, imported);
        await libraryService.saveProject(
          project.copyWith(modified: DateTime.now()),
        );

        ref.invalidate(projectListProvider);
    }
  }

  /// Two separate confirmations, each requiring its own explicit click —
  /// replacing a project's manuscript deletes its current content
  /// (including that content's own Version History, since the scene files
  /// being replaced are deleted first) with no undo.
  Future<bool> _confirmReplace(BuildContext context, Project project) async {
    final firstOk = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace this project\'s manuscript?'),
        content: Text(
          'This deletes every chapter/scene currently in "${project.title}" — including their '
          'Version History — and replaces them with the imported content. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (firstOk != true || !context.mounted) return false;

    final secondOk = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Are you sure?'),
        content: Text(
          '"${project.title}"\'s current manuscript will be permanently deleted right now. '
          'There is no confirmation after this one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete and Replace'),
          ),
        ],
      ),
    );
    return secondOk == true;
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_stories,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'No projects yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text('Start your first novel to see it here.'),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('New Project'),
          ),
        ],
      ),
    );
  }
}

/// A grid entry is either a standalone project or a series (rendered as a
/// stacked-card group of its member projects) — a tiny closed union instead
/// of reusing `Project`/`Series` directly, since the grid needs one combined,
/// sortable list to lay out.
sealed class _LibraryItem {
  DateTime get sortKey;
  int? get sortOrder;
}

class _StandaloneProjectItem extends _LibraryItem {
  _StandaloneProjectItem(this.project);
  final Project project;
  @override
  DateTime get sortKey => project.modified;
  @override
  int? get sortOrder => project.sortOrder;
}

class _SeriesItem extends _LibraryItem {
  _SeriesItem(this.series, this.projects);
  final Series series;
  final List<Project> projects;
  @override
  DateTime get sortKey => projects.isEmpty
      ? series.modified
      : projects.map((p) => p.modified).reduce((a, b) => a.isAfter(b) ? a : b);
  @override
  int? get sortOrder => series.sortOrder;
}

class _LibraryGrid extends ConsumerWidget {
  const _LibraryGrid({required this.projects, required this.series});

  final List<Project> projects;
  final List<Series> series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seriesIds = series.map((s) => s.id).toSet();
    final items =
        <_LibraryItem>[
          for (final project in projects)
            if (project.seriesId == null ||
                !seriesIds.contains(project.seriesId))
              _StandaloneProjectItem(project),
          for (final s in series)
            _SeriesItem(s, projects.where((p) => p.seriesId == s.id).toList()),
        ]..sort((a, b) {
          // Drag-and-drop-ordered items sort first (by their explicit
          // position); anything never manually reordered falls in after them,
          // newest-activity-first — so a freshly created project/series still
          // surfaces near the top without needing a sortOrder of its own.
          final aOrder = a.sortOrder;
          final bOrder = b.sortOrder;
          if (aOrder != null && bOrder != null) return aOrder.compareTo(bOrder);
          if (aOrder != null) return -1;
          if (bOrder != null) return 1;
          return b.sortKey.compareTo(a.sortKey);
        });

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: 172,
        crossAxisSpacing: 12,
        mainAxisSpacing: 20,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final card = switch (item) {
          _StandaloneProjectItem(:final project) => _ProjectCard(
            project: project,
            series: series,
          ),
          _SeriesItem(:final series, :final projects) => _SeriesStackCard(
            series: series,
            projects: projects,
          ),
        };

        return DragTarget<int>(
          onWillAcceptWithDetails: (details) => details.data != index,
          onAcceptWithDetails: (details) =>
              _reorder(ref, items, details.data, index),
          builder: (context, candidateData, rejectedData) => Draggable<int>(
            data: index,
            feedback: Opacity(
              opacity: 0.8,
              child: SizedBox(
                width: 220,
                height: 172,
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

  /// Reassigns sequential `sortOrder` (0..n-1) to every item in the grid's
  /// current order, with [movedIndex]'s item relocated to [targetIndex]
  /// first — only items whose order actually changed get written, so a drop
  /// that doesn't move anything (or moves items far from most of the list)
  /// doesn't rewrite the whole library's `project.json`/series files.
  Future<void> _reorder(
    WidgetRef ref,
    List<_LibraryItem> items,
    int movedIndex,
    int targetIndex,
  ) async {
    final reordered = List<_LibraryItem>.from(items);
    final moved = reordered.removeAt(movedIndex);
    reordered.insert(targetIndex, moved);

    final libraryService = ref.read(libraryServiceProvider);
    final seriesService = ref.read(seriesServiceProvider);
    for (var i = 0; i < reordered.length; i++) {
      final item = reordered[i];
      if (item.sortOrder == i) continue;
      switch (item) {
        case _StandaloneProjectItem(:final project):
          await libraryService.saveProject(project.copyWith(sortOrder: i));
        case _SeriesItem(:final series):
          await seriesService.saveSeries(series.copyWith(sortOrder: i));
      }
    }

    ref.invalidate(projectListProvider);
    ref.invalidate(seriesListProvider);
  }
}

class _ProjectCard extends ConsumerWidget {
  const _ProjectCard({required this.project, required this.series});

  final Project project;
  final List<Series> series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProjectKindFrame(
      kind: project.kind,
      child: Card(
        child: InkWell(
          onTap: () {
            ref.read(openContentIdProvider.notifier).state = null;
            ref.read(currentSeriesProvider.notifier).state = null;
            ref.read(openReferenceProvider.notifier).state = null;
            ref.read(currentProjectProvider.notifier).state = project;
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (project.coverImagePath != null) ...[
                  _CoverThumbnail(project: project),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (project.coverImagePath == null)
                            Icon(
                              ProjectKindStyle.of(project.kind).icon,
                              color: ProjectKindStyle.of(
                                project.kind,
                              ).accent(Theme.of(context).colorScheme),
                            ),
                          const Spacer(),
                          PopupMenuButton<String>(
                            tooltip: 'Project options',
                            icon: const Icon(Icons.more_vert, size: 18),
                            onSelected: (value) {
                              switch (value) {
                                case 'series':
                                  _addToSeries(context, ref);
                                case 'style':
                                  editProjectCardStyle(context, ref, project);
                                case 'archive':
                                  archiveProjectWithConfirmation(
                                    context,
                                    ref,
                                    project,
                                  );
                                case 'delete':
                                  deleteProjectWithConfirmation(
                                    context,
                                    ref,
                                    project,
                                  );
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'series',
                                child: Text('Add to Series…'),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addToSeries(BuildContext context, WidgetRef ref) async {
    final result = await showMoveToSeriesDialog(
      context,
      existingSeries: series,
    );
    if (result == null) return;

    final libraryService = ref.read(libraryServiceProvider);
    if (result.existingSeries != null) {
      await libraryService.saveProject(
        project.copyWith(seriesId: result.existingSeries!.id),
      );
    } else {
      final seriesService = ref.read(seriesServiceProvider);
      final newSeries = await seriesService.createSeries(
        title: result.newSeriesTitle!,
      );
      await libraryService.saveProject(
        project.copyWith(seriesId: newSeries.id),
      );
      ref.invalidate(seriesListProvider);
    }
    ref.invalidate(projectListProvider);
  }
}

/// A series' library card: three faux "cards" stacked with a slight offset
/// so it visually reads as a group before the user even opens it, distinct
/// from a normal single project card.
class _SeriesStackCard extends ConsumerWidget {
  const _SeriesStackCard({required this.series, required this.projects});

  final Series series;
  final List<Project> projects;

  /// The most-recently-modified member with a cover set — an arbitrary but
  /// stable choice for "which cover represents this series" until the app
  /// has a dedicated series-cover concept of its own.
  Project? get _coverSourceProject {
    final withCovers = projects.where((p) => p.coverImagePath != null).toList()
      ..sort((a, b) => b.modified.compareTo(a.modified));
    return withCovers.firstOrNull;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final coverProject = _coverSourceProject;
    return Padding(
      // Room for the two offset cards peeking out above/right of the top one.
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -8,
            right: -8,
            left: 8,
            bottom: 8,
            child: Card(
              color: scheme.surfaceContainerHighest,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: -4,
            right: -4,
            left: 4,
            bottom: 4,
            child: Card(
              color: scheme.surfaceContainerHigh,
              child: const SizedBox.expand(),
            ),
          ),
          Card(
            child: InkWell(
              onTap: () {
                // A stale reference (a character/note left open from
                // whatever series or project was viewed last) shouldn't
                // silently carry into this series' own sidebar/main pane —
                // see openReferenceProvider's doc for why it's a single
                // provider shared across every screen that uses it.
                ref.read(openReferenceProvider.notifier).state = null;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SeriesDetailScreen(series: series),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (coverProject != null) ...[
                      _CoverThumbnail(project: coverProject),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (coverProject == null)
                            Icon(
                              Icons.collections_bookmark,
                              color: scheme.primary,
                            ),
                          const SizedBox(height: 8),
                          Text(
                            series.title,
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),
                          Text(
                            '${projects.length} ${projects.length == 1 ? 'project' : 'projects'}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A project's cover thumbnail — resolves `coverImagePath` to an absolute
/// path via `LibraryService`, shared by the standalone project card and the
/// series stack card's cover-source project.
class _CoverThumbnail extends ConsumerWidget {
  const _CoverThumbnail({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String?>(
      future: ref.read(libraryServiceProvider).coverImageAbsolutePath(project),
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (path == null) return const SizedBox(width: 44, height: 60);
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.file(
            File(path),
            width: 44,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => const SizedBox(
              width: 44,
              height: 60,
              child: Icon(Icons.image_not_supported_outlined, size: 18),
            ),
          ),
        );
      },
    );
  }
}
