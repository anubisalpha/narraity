import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/manuscript.dart';
import '../services/manuscript_service.dart';
import '../state/editor_settings_provider.dart';
import '../state/manuscript_provider.dart';

/// The writing surface for one scene/section: markdown-backed text editor
/// with autosave (debounced), formatting toolbar, find & replace, undo/redo,
/// live word count, and Focus Mode toggle.
class SceneEditor extends ConsumerStatefulWidget {
  const SceneEditor({
    super.key,
    required this.service,
    required this.contentId,
    required this.fallbackTitle,
  });

  final ManuscriptService service;
  final String contentId;
  final String fallbackTitle;

  @override
  ConsumerState<SceneEditor> createState() => _SceneEditorState();
}

class _SceneEditorState extends ConsumerState<SceneEditor> {
  final _controller = TextEditingController();
  final _titleController = TextEditingController();
  final _undoController = UndoHistoryController();
  final _focusNode = FocusNode();

  SceneDoc? _doc;
  Timer? _saveDebounce;
  bool _dirty = false;
  int _wordCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _controller.addListener(_onChanged);
    _titleController.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(SceneEditor old) {
    super.didUpdateWidget(old);
    if (old.contentId != widget.contentId) {
      _flushSave();
      _load();
    }
  }

  Future<void> _load() async {
    final doc = await widget.service.readScene(
      widget.contentId,
      fallbackTitle: widget.fallbackTitle,
    );
    if (!mounted) return;
    setState(() {
      _doc = doc;
      _dirty = false;
      _wordCount = doc.wordCount;
    });
    // Setting .text fires the change listener; reset dirty afterwards.
    _controller.text = doc.content;
    _titleController.text = doc.title;
    _dirty = false;
  }

  void _onChanged() {
    if (_doc == null) return;
    _dirty = true;
    final count = _countWords(_controller.text);
    if (count != _wordCount) setState(() => _wordCount = count);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 1), _flushSave);
  }

  int _countWords(String text) {
    final words = text.trim().split(RegExp(r'\s+'));
    return (words.length == 1 && words.first.isEmpty) ? 0 : words.length;
  }

  Future<void> _flushSave() async {
    _saveDebounce?.cancel();
    final doc = _doc;
    if (doc == null || !_dirty) return;
    doc.content = _controller.text;
    doc.title = _titleController.text.trim().isEmpty
        ? widget.fallbackTitle
        : _titleController.text.trim();
    await widget.service.writeScene(doc);
    _dirty = false;
  }

  @override
  void dispose() {
    _flushSave();
    _saveDebounce?.cancel();
    _controller.dispose();
    _titleController.dispose();
    _undoController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---- formatting ----------------------------------------------------------

  /// Wraps the selection in [marker] (e.g. `**` for bold) — or unwraps it if
  /// already wrapped. With no selection, inserts a marker pair at the caret.
  void _toggleWrap(String marker) {
    final sel = _controller.selection;
    final text = _controller.text;
    if (!sel.isValid) return;

    final selected = sel.textInside(text);
    String replacement;
    if (selected.startsWith(marker) && selected.endsWith(marker) &&
        selected.length >= marker.length * 2) {
      replacement = selected.substring(marker.length, selected.length - marker.length);
    } else {
      replacement = '$marker$selected$marker';
    }
    _controller.value = TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, replacement),
      selection: TextSelection.collapsed(
        offset: sel.start + (selected.isEmpty ? marker.length : replacement.length),
      ),
    );
    _focusNode.requestFocus();
  }

  void _insertBlock(String block) {
    final sel = _controller.selection;
    final text = _controller.text;
    final at = sel.isValid ? sel.start : text.length;
    final needsNewlineBefore = at > 0 && text[at - 1] != '\n';
    final insert = '${needsNewlineBefore ? '\n' : ''}$block\n';
    _controller.value = TextEditingValue(
      text: text.replaceRange(at, sel.isValid ? sel.end : at, insert),
      selection: TextSelection.collapsed(offset: at + insert.length),
    );
    _focusNode.requestFocus();
  }

  Future<void> _findReplace() async {
    final findController = TextEditingController();
    final replaceController = TextEditingController();

    final result = await showDialog<(String, String, bool)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Find & Replace'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: findController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Find'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: replaceController,
              decoration: const InputDecoration(labelText: 'Replace with'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context)
                .pop((findController.text, replaceController.text, false)),
            child: const Text('Replace first'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context)
                .pop((findController.text, replaceController.text, true)),
            child: const Text('Replace all'),
          ),
        ],
      ),
    );

    if (result == null || result.$1.isEmpty) return;
    final (find, replace, all) = result;
    final text = _controller.text;
    if (!text.contains(find)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('"$find" not found')));
      }
      return;
    }
    _controller.text =
        all ? text.replaceAll(find, replace) : text.replaceFirst(find, replace);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(editorSettingsProvider);
    final focusMode = ref.watch(focusModeProvider);

    if (_doc == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final textStyle = TextStyle(
      fontFamily: settings.fontFamily,
      fontSize: settings.fontSize,
      height: settings.lineHeight,
    );

    return Column(
      children: [
        if (!focusMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: TextField(
              controller: _titleController,
              style: Theme.of(context).textTheme.titleLarge,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Scene title',
              ),
            ),
          ),
        if (!focusMode)
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
                IconButton(
                  tooltip: 'Strikethrough',
                  icon: const Icon(Icons.format_strikethrough),
                  onPressed: () => _toggleWrap('~~'),
                ),
                const VerticalDivider(width: 16),
                IconButton(
                  tooltip: 'Scene break',
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () => _insertBlock('***'),
                ),
                IconButton(
                  tooltip: 'Block quote',
                  icon: const Icon(Icons.format_quote),
                  onPressed: () => _insertBlock('> '),
                ),
                IconButton(
                  tooltip: 'Heading',
                  icon: const Icon(Icons.title),
                  onPressed: () => _insertBlock('## '),
                ),
                const VerticalDivider(width: 16),
                ValueListenableBuilder<UndoHistoryValue>(
                  valueListenable: _undoController,
                  builder: (context, value, _) => Row(children: [
                    IconButton(
                      tooltip: 'Undo (Ctrl+Z)',
                      icon: const Icon(Icons.undo),
                      onPressed: value.canUndo ? _undoController.undo : null,
                    ),
                    IconButton(
                      tooltip: 'Redo (Ctrl+Y)',
                      icon: const Icon(Icons.redo),
                      onPressed: value.canRedo ? _undoController.redo : null,
                    ),
                  ]),
                ),
                IconButton(
                  tooltip: 'Find & Replace',
                  icon: const Icon(Icons.find_replace),
                  onPressed: _findReplace,
                ),
                const Spacer(),
                Text('$_wordCount words',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(width: 8),
              ],
            ),
          ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: focusMode ? 96 : 24),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              undoController: _undoController,
              style: textStyle,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Start writing…',
              ),
            ),
          ),
        ),
        if (focusMode)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('$_wordCount words',
                style: Theme.of(context).textTheme.labelSmall),
          ),
      ],
    );
  }
}
