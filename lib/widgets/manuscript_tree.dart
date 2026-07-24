import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/manuscript.dart';
import '../models/project.dart';
import '../services/manuscript_service.dart';
import '../state/manuscript_provider.dart';

/// Sidebar tree: front matter, acts > chapters > scenes (drag-reorder within
/// a chapter), back matter. Selecting an item opens it in the editor.
class ManuscriptTree extends ConsumerWidget {
  const ManuscriptTree({
    super.key,
    required this.project,
    required this.service,
    required this.structure,
  });

  final Project project;
  final ManuscriptService service;
  final ManuscriptStructure structure;

  void _refresh(WidgetRef ref) =>
      ref.invalidate(manuscriptStructureProvider(project));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openId = ref.watch(openContentIdProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final section in structure.frontMatter)
          _SectionTile(
            section: section,
            selected: section.id == openId,
            onDelete: () async {
              await service.deleteSpecialSection(structure, section);
              if (section.id == openId) {
                ref.read(openContentIdProvider.notifier).state = null;
              }
              _refresh(ref);
            },
          ),
        for (final act in structure.acts)
          ExpansionTile(
            key: PageStorageKey('act-${act.id}'),
            initiallyExpanded: true,
            title: Text(act.title, style: Theme.of(context).textTheme.titleSmall),
            trailing: PopupMenuButton<String>(
              onSelected: (action) async {
                if (action == 'addChapter') {
                  await service.addChapter(structure, act);
                  _refresh(ref);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'addChapter', child: Text('Add chapter')),
              ],
            ),
            children: [
              for (final chapter in act.chapters)
                _ChapterTile(
                  project: project,
                  service: service,
                  structure: structure,
                  chapter: chapter,
                ),
            ],
          ),
        for (final section in structure.backMatter)
          _SectionTile(
            section: section,
            selected: section.id == openId,
            onDelete: () async {
              await service.deleteSpecialSection(structure, section);
              if (section.id == openId) {
                ref.read(openContentIdProvider.notifier).state = null;
              }
              _refresh(ref);
            },
          ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Act'),
                onPressed: () async {
                  await service.addAct(structure);
                  _refresh(ref);
                },
              ),
              PopupMenuButton<SpecialSectionType>(
                onSelected: (type) async {
                  final section = await service.addSpecialSection(structure, type);
                  ref.read(openContentIdProvider.notifier).state = section.id;
                  _refresh(ref);
                },
                itemBuilder: (context) => [
                  for (final type in SpecialSectionType.values)
                    PopupMenuItem(value: type, child: Text(type.label)),
                ],
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Front/back matter'),
                  onPressed: null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTile extends ConsumerWidget {
  const _SectionTile({
    required this.section,
    required this.selected,
    required this.onDelete,
  });

  final SpecialSection section;
  final bool selected;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      dense: true,
      selected: selected,
      leading: const Icon(Icons.auto_awesome, size: 18),
      title: Text(section.title),
      onTap: () => ref.read(openContentIdProvider.notifier).state = section.id,
      trailing: PopupMenuButton<String>(
        onSelected: (_) => onDelete(),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

class _ChapterTile extends ConsumerWidget {
  const _ChapterTile({
    required this.project,
    required this.service,
    required this.structure,
    required this.chapter,
  });

  final Project project;
  final ManuscriptService service;
  final ManuscriptStructure structure;
  final ChapterNode chapter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openId = ref.watch(openContentIdProvider);

    return ExpansionTile(
      key: PageStorageKey('chapter-${chapter.id}'),
      initiallyExpanded: true,
      tilePadding: const EdgeInsets.only(left: 16, right: 8),
      title: Text(chapter.title),
      trailing: PopupMenuButton<String>(
        onSelected: (action) async {
          if (action == 'addScene') {
            final scene = await service.addScene(structure, chapter);
            ref.read(openContentIdProvider.notifier).state = scene.id;
            ref.invalidate(manuscriptStructureProvider(project));
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'addScene', child: Text('Add scene')),
        ],
      ),
      children: [
        ReorderableListView.builder(
          // Explicit key required: without one, this nested list's PageStorage
          // slot can collide with the parent ExpansionTile's (which stores a
          // bool for expanded state), causing "bool is not a subtype of
          // double?" when this list tries to restore a scroll offset.
          key: PageStorageKey('scenes-${chapter.id}'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: chapter.scenes.length,
          onReorder: (oldIndex, newIndex) async {
            await service.reorderScene(structure, chapter, oldIndex, newIndex);
            ref.invalidate(manuscriptStructureProvider(project));
          },
          itemBuilder: (context, index) {
            final scene = chapter.scenes[index];
            return ReorderableDragStartListener(
              key: ValueKey(scene.id),
              index: index,
              child: ListTile(
                dense: true,
                selected: scene.id == openId,
                contentPadding: const EdgeInsets.only(left: 32, right: 8),
                leading: const Icon(Icons.description_outlined, size: 18),
                title: Text(scene.title, overflow: TextOverflow.ellipsis),
                onTap: () =>
                    ref.read(openContentIdProvider.notifier).state = scene.id,
                trailing: PopupMenuButton<String>(
                  onSelected: (action) async {
                    if (action == 'delete') {
                      await service.deleteScene(structure, chapter, scene);
                      if (scene.id == openId) {
                        ref.read(openContentIdProvider.notifier).state = null;
                      }
                      ref.invalidate(manuscriptStructureProvider(project));
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
