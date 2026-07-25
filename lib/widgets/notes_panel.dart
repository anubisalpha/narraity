import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../models/story_note.dart';
import '../services/story_notes_service.dart';
import '../state/reference_provider.dart';

/// Sidebar for Story Notes: a search box, then either ranked search results or
/// the folder tree (root notes first, then one section per folder).
class NotesPanel extends ConsumerWidget {
  const NotesPanel({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(noteSearchQueryProvider);
    final service = ref.watch(storyNotesServiceProvider(project)).valueOrNull;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: _SearchField(project: project),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.note_add_outlined, size: 18),
                  label: const Text('Note'),
                  onPressed:
                      service == null ? null : () => _createNote(context, ref, service),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'New folder',
                icon: const Icon(Icons.create_new_folder_outlined),
                onPressed:
                    service == null ? null : () => _createFolder(context, ref, service),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: query.trim().isEmpty
              ? _NoteTree(project: project, service: service)
              : _SearchResults(project: project, service: service),
        ),
      ],
    );
  }

  Future<void> _createNote(
    BuildContext context,
    WidgetRef ref,
    StoryNotesService service, {
    String? folder,
  }) async {
    final created = await service.createNote(folder: folder);
    invalidateReferences(ref, project);
    ref.read(openReferenceProvider.notifier).state =
        ReferenceSelection(ReferenceKind.note, created.id);
  }

  Future<void> _createFolder(
    BuildContext context,
    WidgetRef ref,
    StoryNotesService service,
  ) async {
    final name = await _promptForText(context, title: 'New folder', label: 'Folder name');
    if (name == null || name.trim().isEmpty) return;
    await service.createFolder(name);
    invalidateReferences(ref, project);
  }
}

Future<String?> _promptForText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField({required this.project});

  final Project project;

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(noteSearchQueryProvider);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(noteSearchQueryProvider);

    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        hintText: 'Search notes…',
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 18),
        border: const OutlineInputBorder(),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear, size: 18),
                tooltip: 'Clear search',
                onPressed: () {
                  _controller.clear();
                  ref.read(noteSearchQueryProvider.notifier).state = '';
                },
              ),
      ),
      onChanged: (value) => ref.read(noteSearchQueryProvider.notifier).state = value,
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.project, required this.service});

  final Project project;
  final StoryNotesService? service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(noteSearchResultsProvider(project));

    return resultsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Search failed: $err')),
      data: (results) => results.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No notes match that search.'),
            )
          : ListView(
              children: [
                for (final note in results)
                  _NoteTile(project: project, note: note, service: service),
              ],
            ),
    );
  }
}

class _NoteTree extends ConsumerWidget {
  const _NoteTree({required this.project, required this.service});

  final Project project;
  final StoryNotesService? service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(storyNoteListProvider(project));
    final foldersAsync = ref.watch(noteFoldersProvider(project));

    return notesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Failed to load notes: $err')),
      data: (notes) {
        final folders = foldersAsync.valueOrNull ?? const <String>[];
        final rootNotes = notes.where((n) => n.folder == null).toList();

        if (notes.isEmpty && folders.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No notes yet.'),
          );
        }

        return ListView(
          children: [
            for (final note in rootNotes)
              _NoteTile(project: project, note: note, service: service),
            for (final folder in folders)
              _FolderSection(
                project: project,
                folder: folder,
                notes: notes.where((n) => n.folder == folder).toList(),
                service: service,
              ),
          ],
        );
      },
    );
  }
}

class _FolderSection extends ConsumerWidget {
  const _FolderSection({
    required this.project,
    required this.folder,
    required this.notes,
    required this.service,
  });

  final Project project;
  final String folder;
  final List<StoryNote> notes;
  final StoryNotesService? service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExpansionTile(
      dense: true,
      initiallyExpanded: true,
      leading: const Icon(Icons.folder_outlined, size: 20),
      title: Text(folder, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (action) => _handle(context, ref, action),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'note', child: Text('New note here')),
          PopupMenuItem(value: 'rename', child: Text('Rename folder')),
          PopupMenuItem(value: 'delete', child: Text('Delete folder')),
        ],
      ),
      children: [
        if (notes.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(32, 4, 8, 8),
            child: Text('Empty', style: TextStyle(fontStyle: FontStyle.italic)),
          ),
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: _NoteTile(project: project, note: note, service: service),
          ),
      ],
    );
  }

  Future<void> _handle(BuildContext context, WidgetRef ref, String action) async {
    final service = this.service;
    if (service == null) return;

    switch (action) {
      case 'note':
        final created = await service.createNote(folder: folder);
        invalidateReferences(ref, project);
        ref.read(openReferenceProvider.notifier).state =
            ReferenceSelection(ReferenceKind.note, created.id);
      case 'rename':
        if (!context.mounted) return;
        final name = await _promptForText(
          context,
          title: 'Rename folder',
          label: 'Folder name',
          initial: folder,
        );
        if (name == null || name.trim().isEmpty) return;
        await service.renameFolder(folder, name);
        invalidateReferences(ref, project);
      case 'delete':
        if (!context.mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete "$folder"?'),
            content: Text(
              notes.isEmpty
                  ? 'The folder is empty and will be removed.'
                  : 'The ${notes.length} note${notes.length == 1 ? '' : 's'} inside will '
                      'be moved back to the top level, not deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete folder'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await service.deleteFolder(folder);
        invalidateReferences(ref, project);
    }
  }
}

class _NoteTile extends ConsumerWidget {
  const _NoteTile({required this.project, required this.note, required this.service});

  final Project project;
  final StoryNote note;
  final StoryNotesService? service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(openReferenceProvider);
    final isOpen = selection?.kind == ReferenceKind.note && selection?.id == note.id;
    final folders = ref.watch(noteFoldersProvider(project)).valueOrNull ?? const [];

    return ListTile(
      dense: true,
      selected: isOpen,
      leading: Icon(
        note.source == 'globalIdea' ? Icons.lightbulb_outline : Icons.sticky_note_2_outlined,
        size: 20,
      ),
      title: Text(
        note.title.trim().isEmpty ? 'Untitled note' : note.title,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: note.tags.isEmpty
          ? null
          : Text(note.tags.map((t) => '#$t').join(' '),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (action) => _handle(context, ref, action, folders),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'move', child: Text('Move to folder…')),
          const PopupMenuItem(value: 'delete', child: Text('Delete note')),
        ],
      ),
      onTap: () => ref.read(openReferenceProvider.notifier).state =
          ReferenceSelection(ReferenceKind.note, note.id),
    );
  }

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    String action,
    List<String> folders,
  ) async {
    final service = this.service;
    if (service == null) return;

    if (action == 'move') {
      final target = await showDialog<String?>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Move note to'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(''),
              child: const Text('Top level'),
            ),
            for (final folder in folders)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(folder),
                child: Text(folder),
              ),
          ],
        ),
      );
      if (target == null) return;
      await service.moveToFolder(note, target.isEmpty ? null : target);
      invalidateReferences(ref, project);
      return;
    }

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${note.title}"?'),
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

    await service.delete(note);
    final selection = ref.read(openReferenceProvider);
    if (selection?.id == note.id) {
      ref.read(openReferenceProvider.notifier).state = null;
    }
    invalidateReferences(ref, project);
  }
}
