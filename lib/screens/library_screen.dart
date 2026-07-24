import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/project.dart';
import '../state/library_provider.dart';
import '../state/manuscript_provider.dart';
import '../state/theme_provider.dart';
import '../widgets/new_project_dialog.dart';
import '../widgets/quick_capture_dialog.dart';
import 'ideas_screen.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectListProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Narraity'),
        actions: [
          IconButton(
            tooltip: 'New Idea',
            icon: const Icon(Icons.lightbulb_outline),
            onPressed: () => showQuickCaptureDialog(context, ref),
          ),
          IconButton(
            tooltip: 'Global Ideas',
            icon: const Icon(Icons.tips_and_updates_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const IdeasScreen()),
            ),
          ),
          PopupMenuButton<ThemeMode>(
            tooltip: 'Theme',
            icon: Icon(switch (themeMode) {
              ThemeMode.light => Icons.light_mode,
              ThemeMode.dark => Icons.dark_mode,
              ThemeMode.system => Icons.brightness_auto,
            }),
            onSelected: (mode) => ref.read(themeModeProvider.notifier).setThemeMode(mode),
            itemBuilder: (context) => const [
              PopupMenuItem(value: ThemeMode.system, child: Text('System')),
              PopupMenuItem(value: ThemeMode.light, child: Text('Light')),
              PopupMenuItem(value: ThemeMode.dark, child: Text('Dark')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: projectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Failed to load library: $err')),
        data: (projects) => projects.isEmpty
            ? _EmptyLibrary(onCreate: () => _createProject(context, ref))
            : _ProjectGrid(projects: projects),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createProject(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New Project'),
      ),
    );
  }

  Future<void> _createProject(BuildContext context, WidgetRef ref) async {
    final result = await showNewProjectDialog(context);
    if (result == null) return;

    final service = ref.read(libraryServiceProvider);
    final project = await service.createProject(title: result.title, author: result.author);
    ref.invalidate(projectListProvider);
    ref.read(openContentIdProvider.notifier).state = null;
    ref.read(currentProjectProvider.notifier).state = project;
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
          Icon(Icons.auto_stories, size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('No projects yet', style: Theme.of(context).textTheme.titleLarge),
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

class _ProjectGrid extends ConsumerWidget {
  const _ProjectGrid({required this.projects});

  final List<Project> projects;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: 160,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: projects.length,
      itemBuilder: (context, index) {
        final project = projects[index];
        return Card(
          child: InkWell(
            onTap: () {
              ref.read(openContentIdProvider.notifier).state = null;
              ref.read(currentProjectProvider.notifier).state = project;
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.menu_book, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 8),
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
        );
      },
    );
  }
}
