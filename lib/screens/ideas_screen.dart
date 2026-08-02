import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/idea.dart';
import '../models/project.dart';
import '../state/ideas_provider.dart';
import '../state/library_provider.dart';
import '../widgets/quick_capture_dialog.dart';

/// Flat, searchable, tag-filterable list of captured ideas, with the
/// promotion path (new project / attach to existing) per PLAN.md.
class IdeasScreen extends ConsumerWidget {
  const IdeasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ideasAsync = ref.watch(ideaListProvider);
    final search = ref.watch(ideaSearchProvider);
    final tagFilter = ref.watch(ideaTagFilterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Global Ideas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showQuickCaptureDialog(context, ref),
        icon: const Icon(Icons.lightbulb_outline),
        label: const Text('New Idea'),
      ),
      body: ideasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Failed to load ideas: $err')),
        data: (ideas) {
          final allTags = {for (final i in ideas) ...i.tags}.toList()..sort();
          final visible = ideas.where((idea) {
            if (tagFilter != null && !idea.tags.contains(tagFilter)) return false;
            if (search.isEmpty) return true;
            final q = search.toLowerCase();
            return idea.title.toLowerCase().contains(q) ||
                idea.body.toLowerCase().contains(q) ||
                idea.tags.any((t) => t.toLowerCase().contains(q));
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search ideas…',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => ref.read(ideaSearchProvider.notifier).state = value,
                ),
              ),
              if (allTags.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: tagFilter == null,
                        onSelected: (_) =>
                            ref.read(ideaTagFilterProvider.notifier).state = null,
                      ),
                      for (final tag in allTags) ...[
                        const SizedBox(width: 8),
                        FilterChip(
                          label: Text(tag),
                          selected: tagFilter == tag,
                          onSelected: (_) =>
                              ref.read(ideaTagFilterProvider.notifier).state =
                                  tagFilter == tag ? null : tag,
                        ),
                      ],
                    ],
                  ),
                ),
              Expanded(
                child: visible.isEmpty
                    ? const Center(child: Text('No ideas yet — capture one!'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                        itemCount: visible.length,
                        itemBuilder: (context, index) =>
                            _IdeaCard(idea: visible[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _IdeaCard extends ConsumerWidget {
  const _IdeaCard({required this.idea});

  final Idea idea;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final used = idea.status == IdeaStatus.used;

    return Card(
      child: ListTile(
        leading: Icon(
          used ? Icons.check_circle_outline : Icons.lightbulb_outline,
          color: used ? Colors.green : Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          idea.title,
          style: used ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (idea.body.isNotEmpty)
              Text(idea.body, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  DateFormat.yMMMd().format(idea.created),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                for (final tag in idea.tags)
                  Chip(
                    label: Text(tag),
                    labelStyle: Theme.of(context).textTheme.labelSmall,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                if (used)
                  Text('used', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) => _handleAction(context, ref, action),
          itemBuilder: (context) => [
            if (!used) ...[
              const PopupMenuItem(
                value: 'promote',
                child: Text('Promote to new project'),
              ),
              const PopupMenuItem(
                value: 'attach',
                child: Text('Attach to existing project…'),
              ),
            ],
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, WidgetRef ref, String action) async {
    final service = ref.read(ideasServiceProvider);
    final messenger = ScaffoldMessenger.of(context);

    switch (action) {
      case 'promote':
        final project = await service.promoteToNewProject(idea);
        ref.invalidate(ideaListProvider);
        ref.invalidate(projectListProvider);
        messenger.showSnackBar(
          SnackBar(content: Text('Created project "${project.title}" from idea')),
        );
      case 'attach':
        if (!context.mounted) return;
        final project = await _pickProject(context, ref);
        if (project == null) return;
        await service.attachToProject(idea, project);
        ref.invalidate(ideaListProvider);
        messenger.showSnackBar(
          SnackBar(content: Text('Attached to "${project.title}" as a story note')),
        );
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete "${idea.title}"?'),
            content: const Text('This cannot be undone from within the app.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;

        await service.deleteIdea(idea);
        ref.invalidate(ideaListProvider);
    }
  }

  Future<Project?> _pickProject(BuildContext context, WidgetRef ref) async {
    final projects = await ref.read(projectListProvider.future);
    if (!context.mounted) return null;
    if (projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No projects to attach to yet')),
      );
      return null;
    }
    return showDialog<Project>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Attach to project'),
        children: [
          for (final project in projects)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(project),
              child: Text(project.title),
            ),
        ],
      ),
    );
  }
}
