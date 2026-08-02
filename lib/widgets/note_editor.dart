import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/content_owner.dart';
import '../models/story_note.dart';
import '../services/story_notes_service.dart';
import '../state/editor_settings_provider.dart';
import '../state/reference_provider.dart';

/// Main-pane editor for one story note: title, tags, and a markdown body,
/// autosaved on the same debounce as the scene editor. Shared between a
/// project and a series (see [ContentOwner]).
class NoteEditor extends ConsumerStatefulWidget {
  const NoteEditor({super.key, required this.owner, required this.noteId});

  final ContentOwner owner;
  final String noteId;

  @override
  ConsumerState<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<NoteEditor> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _bodyFocus = FocusNode();

  StoryNotesService? _service;
  StoryNote? _note;
  Timer? _saveDebounce;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
    _titleController.addListener(_onChanged);
    _bodyController.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(NoteEditor old) {
    super.didUpdateWidget(old);
    if (old.noteId != widget.noteId) {
      _flushSave();
      _load();
    }
  }

  @override
  void dispose() {
    _flushSave();
    _saveDebounce?.cancel();
    _titleController.dispose();
    _bodyController.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service = await ref.read(storyNotesServiceProvider(widget.owner).future);
    final notes = await service.listAll();
    final note = notes.where((n) => n.id == widget.noteId).firstOrNull;
    if (!mounted || note == null) return;

    setState(() {
      _service = service;
      _note = note;
    });
    _titleController.text = note.title;
    _bodyController.text = note.body;
    _dirty = false;
  }

  void _onChanged() {
    if (_note == null) return;
    _dirty = true;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 1), _flushSave);
  }

  Future<void> _flushSave() async {
    _saveDebounce?.cancel();
    final note = _note;
    final service = _service;
    if (note == null || service == null || !_dirty) return;

    final updated = note.copyWith(
      title: _titleController.text,
      body: _bodyController.text,
    );
    await service.save(updated);
    _note = updated;
    _dirty = false;
    if (mounted) invalidateReferences(ref, widget.owner);
  }

  Future<void> _addTag() async {
    final note = _note;
    if (note == null) return;

    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tag', hintText: 'plot, theme…'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    final trimmed = tag?.trim().replaceAll('#', '');
    if (trimmed == null || trimmed.isEmpty || note.tags.contains(trimmed)) return;
    await _saveTags([...note.tags, trimmed]);
  }

  Future<void> _removeTag(String tag) =>
      _saveTags(_note!.tags.where((t) => t != tag).toList());

  Future<void> _saveTags(List<String> tags) async {
    final note = _note;
    final service = _service;
    if (note == null || service == null) return;

    // Flush any pending text edits first so saving tags can't overwrite them
    // with the stale copy held in _note.
    await _flushSave();
    final updated = (_note ?? note).copyWith(tags: tags);
    await service.save(updated);
    setState(() => _note = updated);
    if (mounted) invalidateReferences(ref, widget.owner);
  }

  /// Wraps the selection in [marker], or inserts a marker pair at the caret —
  /// the same lightweight markdown affordance the scene editor offers, kept
  /// local so the two can diverge without either destabilising the other.
  void _toggleWrap(String marker) {
    final selection = _bodyController.selection;
    final text = _bodyController.text;
    if (!selection.isValid) return;

    final selected = selection.textInside(text);
    final isWrapped = selected.startsWith(marker) &&
        selected.endsWith(marker) &&
        selected.length >= marker.length * 2;
    final replacement = isWrapped
        ? selected.substring(marker.length, selected.length - marker.length)
        : '$marker$selected$marker';

    _bodyController.value = TextEditingValue(
      text: text.replaceRange(selection.start, selection.end, replacement),
      selection: TextSelection.collapsed(
        offset: selection.start +
            (selected.isEmpty ? marker.length : replacement.length),
      ),
    );
    _bodyFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    if (note == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final settings = ref.watch(editorSettingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: TextField(
            controller: _titleController,
            style: Theme.of(context).textTheme.titleLarge,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Note title',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final tag in note.tags)
                Chip(
                  label: Text(tag),
                  visualDensity: VisualDensity.compact,
                  onDeleted: () => _removeTag(tag),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('Tag'),
                visualDensity: VisualDensity.compact,
                onPressed: _addTag,
              ),
              if (note.folder != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    'in ${note.folder}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Bold',
                icon: const Icon(Icons.format_bold),
                onPressed: () => _toggleWrap('**'),
              ),
              IconButton(
                tooltip: 'Italic',
                icon: const Icon(Icons.format_italic),
                onPressed: () => _toggleWrap('*'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: TextField(
              controller: _bodyController,
              focusNode: _bodyFocus,
              style: TextStyle(
                fontFamily: settings.fontFamily,
                fontSize: settings.fontSize,
                height: settings.lineHeight,
              ),
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Write your note…',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
