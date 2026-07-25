import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile_entry.dart';
import '../models/project.dart';
import '../services/profile_service.dart';
import '../state/reference_panel_provider.dart';
import '../state/reference_provider.dart';

/// Sidebar list of character profiles or worldbuilding entries.
///
/// One widget serves both: characters are a flat alphabetical list, world
/// entries are grouped under their category (uncategorised first). Everything
/// else — tiles, add, rename-by-opening, delete — is identical.
class ProfilePanel extends ConsumerWidget {
  const ProfilePanel({super.key, required this.project, required this.kind});

  final Project project;
  final ProfileKind kind;

  bool get _isCharacter => kind == ProfileKind.character;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listProvider =
        _isCharacter ? characterListProvider(project) : worldListProvider(project);
    final serviceProvider =
        _isCharacter ? characterServiceProvider(project) : worldServiceProvider(project);

    final entriesAsync = ref.watch(listProvider);
    final service = ref.watch(serviceProvider).valueOrNull;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(_isCharacter ? 'New character' : 'New entry'),
              onPressed: service == null ? null : () => _create(context, ref, service),
            ),
          ),
        ),
        Expanded(
          child: entriesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Failed to load: $err')),
            data: (entries) {
              if (entries.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _isCharacter
                        ? 'No characters yet.'
                        : 'No worldbuilding entries yet.',
                  ),
                );
              }
              return ListView(
                children: _isCharacter
                    ? [
                        for (final entry in entries)
                          _EntryTile(
                            project: project,
                            kind: kind,
                            entry: entry,
                            service: service,
                          ),
                      ]
                    : _groupedByCategory(entries, service),
              );
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _groupedByCategory(List<ProfileEntry> entries, ProfileService? service) {
    final uncategorised = entries
        .where((e) => e.category == null || e.category!.trim().isEmpty)
        .toList();
    final categories = entries
        .map((e) => e.category)
        .whereType<String>()
        .where((c) => c.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return [
      // Uncategorised entries sit at the top rather than under an "Other"
      // heading — they're usually the ones still being sorted out.
      for (final entry in uncategorised)
        _EntryTile(project: project, kind: kind, entry: entry, service: service),
      for (final category in categories)
        ExpansionTile(
          initiallyExpanded: true,
          dense: true,
          title: Text(category, style: const TextStyle(fontWeight: FontWeight.w600)),
          children: [
            for (final entry in entries.where((e) => e.category == category))
              _EntryTile(project: project, kind: kind, entry: entry, service: service),
          ],
        ),
    ];
  }

  Future<void> _create(BuildContext context, WidgetRef ref, ProfileService service) async {
    final existingCategories = _isCharacter
        ? const <String>[]
        : (ref.read(worldCategoriesProvider(project)).valueOrNull ?? const <String>[]);

    final result = await showDialog<(String name, String? category)>(
      context: context,
      builder: (_) => _NewEntryDialog(
        title: _isCharacter ? 'New character' : 'New worldbuilding entry',
        askForCategory: !_isCharacter,
        existingCategories: existingCategories,
      ),
    );
    if (result == null) return;

    final created = await service.create(name: result.$1, category: result.$2);
    invalidateReferences(ref, project);
    ref.read(openReferenceProvider.notifier).state = ReferenceSelection(
      _isCharacter ? ReferenceKind.character : ReferenceKind.world,
      created.id,
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({
    required this.project,
    required this.kind,
    required this.entry,
    required this.service,
  });

  final Project project;
  final ProfileKind kind;
  final ProfileEntry entry;
  final ProfileService? service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(openReferenceProvider);
    final referenceKind =
        kind == ProfileKind.character ? ReferenceKind.character : ReferenceKind.world;
    final isOpen = selection?.kind == referenceKind && selection?.id == entry.id;

    final imageFile = service?.imageFile(entry);
    final hasImage = imageFile != null && imageFile.existsSync();
    final isPinned = ref.watch(pinnedReferencesProvider(project)).contains(entry.id);

    return ListTile(
      dense: true,
      selected: isOpen,
      leading: CircleAvatar(
        radius: 16,
        foregroundImage: hasImage ? FileImage(imageFile) : null,
        child: Text(_initials(entry.name)),
      ),
      title: Text(entry.name, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPinned)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.push_pin, size: 14),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18),
            tooltip: 'Options',
            onSelected: (action) {
              if (action == 'pin') {
                ref.read(pinnedReferencesProvider(project).notifier).toggle(entry.id);
              } else {
                _confirmDelete(context, ref);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'pin',
                child: Text(isPinned ? 'Unpin from panel' : 'Pin to Reference Panel'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      onTap: () => ref.read(openReferenceProvider.notifier).state =
          ReferenceSelection(referenceKind, entry.id),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${entry.name}"?'),
        content: const Text(
          'The profile and its image are removed from this project. This cannot be '
          'undone from within the app — an earlier vault backup would still have it.',
        ),
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
    if (confirmed != true || service == null) return;

    await service!.delete(entry);
    final selection = ref.read(openReferenceProvider);
    if (selection?.id == entry.id) {
      ref.read(openReferenceProvider.notifier).state = null;
    }
    invalidateReferences(ref, project);
  }
}

class _NewEntryDialog extends StatefulWidget {
  const _NewEntryDialog({
    required this.title,
    required this.askForCategory,
    required this.existingCategories,
  });

  final String title;
  final bool askForCategory;
  final List<String> existingCategories;

  @override
  State<_NewEntryDialog> createState() => _NewEntryDialogState();
}

class _NewEntryDialogState extends State<_NewEntryDialog> {
  final _name = TextEditingController();
  final _category = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    final category = _category.text.trim();
    Navigator.of(context).pop((name, category.isEmpty ? null : category));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(labelText: 'Name', errorText: _error),
            ),
            if (widget.askForCategory) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _category,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Category (optional)',
                  hintText: 'Location, Faction, Magic…',
                ),
              ),
              if (widget.existingCategories.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final category in widget.existingCategories)
                      ActionChip(
                        label: Text(category),
                        onPressed: () => _category.text = category,
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
