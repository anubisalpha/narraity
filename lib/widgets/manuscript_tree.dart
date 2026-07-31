import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/manuscript.dart';
import '../models/project.dart';
import '../screens/section_overview_screen.dart';
import '../services/manuscript_service.dart';
import '../state/library_provider.dart';
import '../state/manuscript_provider.dart';
import '../state/reference_provider.dart';

/// Sidebar tree: front matter, then a generic arbitrary-depth node tree
/// (drag-reorder within any level), then back matter. Every node — at any
/// depth — can have children added under it with a freeform label
/// ("Chapter", "Act", "Book", ...), so the tree isn't locked to any fixed
/// shape once the project exists; see manuscript_seeds.dart for the
/// one-click starting shapes offered at project creation.
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

  void _refresh(WidgetRef ref) => ref.invalidate(manuscriptStructureProvider(project));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openId = ref.watch(openContentIdProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _CoverTile(project: project),
        const Divider(height: 1),
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
        _NodeList(
          project: project,
          service: service,
          structure: structure,
          parent: null,
          nodes: structure.nodes,
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
                label: const Text('Section'),
                onPressed: () async {
                  final label = await _showAddChildDialog(context);
                  if (label == null) return;
                  final node = await service.addNode(
                    structure,
                    typeLabel: label,
                    parent: null,
                  );
                  openScene(ref, node.id);
                  _refresh(ref);
                },
              ),
              PopupMenuButton<SpecialSectionType>(
                onSelected: (type) async {
                  final section = await service.addSpecialSection(structure, type);
                  openScene(ref, section.id);
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

/// A persistent row above front matter for the project's (single, optional)
/// cover image — shown here rather than folded into the "+Front/back matter"
/// menu since a cover is one image file per project, not a repeatable prose
/// section backed by its own scene file. Also drives the thumbnail shown on
/// this project's Library card.
class _CoverTile extends ConsumerWidget {
  const _CoverTile({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasCover = project.coverImagePath != null;
    return ListTile(
      dense: true,
      leading: hasCover
          ? FutureBuilder<String?>(
              future: ref.read(libraryServiceProvider).coverImageAbsolutePath(project),
              builder: (context, snapshot) {
                final path = snapshot.data;
                if (path == null) return const SizedBox(width: 28, height: 36);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.file(
                    File(path),
                    width: 28,
                    height: 36,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) =>
                        const Icon(Icons.image_not_supported_outlined, size: 18),
                  ),
                );
              },
            )
          : const Icon(Icons.image_outlined, size: 18),
      title: Text(hasCover ? 'Front Cover' : 'Add Front Cover'),
      onTap: () => hasCover ? _showOptions(context, ref) : _pickCover(context, ref),
    );
  }

  Future<void> _pickCover(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Choose a front cover image',
      type: FileType.image,
      lockParentWindow: true,
    );
    final path = result?.files.single.path;
    if (path == null) return;

    final library = ref.read(libraryServiceProvider);
    final updated = await library.setCoverImage(project, File(path));
    ref.invalidate(projectListProvider);
    if (ref.read(currentProjectProvider)?.id == updated.id) {
      ref.read(currentProjectProvider.notifier).state = updated;
    }
  }

  Future<void> _showOptions(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Replace Cover'),
              onTap: () => Navigator.of(context).pop('replace'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove Cover'),
              onTap: () => Navigator.of(context).pop('remove'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;

    if (action == 'replace') {
      await _pickCover(context, ref);
    } else if (action == 'remove') {
      final library = ref.read(libraryServiceProvider);
      final updated = await library.removeCoverImage(project);
      ref.invalidate(projectListProvider);
      if (ref.read(currentProjectProvider)?.id == updated.id) {
        ref.read(currentProjectProvider.notifier).state = updated;
      }
    }
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
      onTap: () => openScene(ref, section.id),
      trailing: PopupMenuButton<String>(
        onSelected: (_) => onDelete(),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

/// A reorderable list of sibling nodes — used both for the top level and
/// for any container's children, so the same drag-reorder logic works at
/// every depth.
class _NodeList extends ConsumerWidget {
  const _NodeList({
    required this.project,
    required this.service,
    required this.structure,
    required this.parent,
    required this.nodes,
  });

  final Project project;
  final ManuscriptService service;
  final ManuscriptStructure structure;
  final ManuscriptNode? parent;
  final List<ManuscriptNode> nodes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ReorderableListView.builder(
      // Explicit key required: without one, a nested list's PageStorage slot
      // can collide with an ancestor ExpansionTile's (which stores a bool
      // for expanded state), causing "bool is not a subtype of double?" when
      // this list tries to restore a scroll offset.
      key: PageStorageKey('nodes-${parent?.id ?? 'root'}'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: nodes.length,
      onReorder: (oldIndex, newIndex) async {
        await service.reorderNode(structure, parent, oldIndex, newIndex);
        ref.invalidate(manuscriptStructureProvider(project));
      },
      itemBuilder: (context, index) {
        final node = nodes[index];
        return ReorderableDragStartListener(
          key: ValueKey(node.id),
          index: index,
          child: _NodeTile(
            project: project,
            service: service,
            structure: structure,
            node: node,
          ),
        );
      },
    );
  }
}

/// A node's row: tapping it opens its own prose in the editor, regardless of
/// whether it also has subsections. The expand/collapse chevron (present
/// only once it has children) reveals those subsections underneath without
/// affecting the tap-to-open behavior — writing and organizing are
/// independent actions on the same node.
class _NodeTile extends ConsumerStatefulWidget {
  const _NodeTile({
    required this.project,
    required this.service,
    required this.structure,
    required this.node,
  });

  final Project project;
  final ManuscriptService service;
  final ManuscriptStructure structure;
  final ManuscriptNode node;

  @override
  ConsumerState<_NodeTile> createState() => _NodeTileState();
}

class _NodeTileState extends ConsumerState<_NodeTile> {
  bool _expanded = true;

  void _refresh() => ref.invalidate(manuscriptStructureProvider(widget.project));

  Future<void> _delete(String? openId) async {
    await widget.service.deleteNode(widget.structure, widget.node);
    if (widget.node.contentIds.contains(openId)) {
      ref.read(openContentIdProvider.notifier).state = null;
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final openId = ref.watch(openContentIdProvider);
    final hasChildren = node.children.isNotEmpty;
    final itemCount = ManuscriptStructure.contentCount(node);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          selected: node.id == openId,
          leading: hasChildren
              ? IconButton(
                  icon: Icon(_expanded ? Icons.expand_more : Icons.chevron_right),
                  tooltip: _expanded ? 'Collapse' : 'Expand',
                  onPressed: () => setState(() => _expanded = !_expanded),
                )
              : const Icon(Icons.description_outlined, size: 18),
          title: Text(node.title, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            hasChildren
                ? '${node.typeLabel} · $itemCount ${itemCount == 1 ? 'item' : 'items'}'
                : node.typeLabel,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          onTap: () => openScene(ref, node.id),
          trailing: PopupMenuButton<String>(
            onSelected: (action) async {
              switch (action) {
                case 'addChild':
                  final label = await _showAddChildDialog(context);
                  if (label == null) return;
                  await widget.service
                      .addNode(widget.structure, typeLabel: label, parent: node);
                  setState(() => _expanded = true);
                  _refresh();
                case 'overview':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          SectionOverviewScreen(service: widget.service, node: node),
                    ),
                  );
                case 'toggleShowTitle':
                  await widget.service.setShowTitleInExport(
                      widget.structure, node, !node.showTitleInExport);
                  _refresh();
                case 'delete':
                  await _delete(openId);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'addChild', child: Text('Add subsection here')),
              if (hasChildren)
                const PopupMenuItem(
                    value: 'overview', child: Text('View everything in this section')),
              CheckedPopupMenuItem(
                value: 'toggleShowTitle',
                checked: node.showTitleInExport,
                child: const Text('Print title in exports'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),
        if (hasChildren && _expanded)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: _NodeList(
              project: widget.project,
              service: widget.service,
              structure: widget.structure,
              parent: node,
              nodes: node.children,
            ),
          ),
      ],
    );
  }
}

/// Prompts for a freeform type label ("Chapter", "Act", "Book", "Scene",
/// ...) for a new node. Returns null if cancelled. Every node can hold
/// prose and have subsections at once, so there's no "container vs. leaf"
/// choice to make here.
Future<String?> _showAddChildDialog(BuildContext context) {
  final labelController = TextEditingController(text: 'Chapter');

  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add Section'),
      content: TextField(
        controller: labelController,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'What is this?',
          hintText: 'Chapter, Act, Book, Part, Scene…',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final label = labelController.text.trim();
            if (label.isEmpty) return;
            Navigator.of(context).pop(label);
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
}
