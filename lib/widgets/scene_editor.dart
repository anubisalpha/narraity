import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/manuscript.dart';
import '../models/profile_entry.dart';
import '../models/project.dart';
import '../screens/scene_history_screen.dart';
import '../services/dictation_engine.dart';
import '../services/manuscript_service.dart';
import '../services/mention_scanner.dart';
import '../services/voice_command_processor.dart';
import '../state/dictation_provider.dart';
import '../state/editor_settings_provider.dart';
import '../state/manuscript_provider.dart';
import '../state/reference_panel_provider.dart';
import '../state/reference_provider.dart';
import '../state/scene_history_provider.dart';
import 'dictation_model_dialog.dart';

/// The writing surface for one scene/section: markdown-backed text editor
/// with autosave (debounced), formatting toolbar, find & replace, undo/redo,
/// live word count, Version History, and Focus Mode toggle.
class SceneEditor extends ConsumerStatefulWidget {
  const SceneEditor({
    super.key,
    required this.project,
    required this.service,
    required this.contentId,
    required this.fallbackTitle,
  });

  final Project project;
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

  Timer? _snapshotDebounce;
  int _wordsAtLastSnapshot = 0;

  DictationEngine? _dictationEngine;
  bool _isDictating = false;
  bool _dictationBusy = false;
  List<(int start, int end)> _unreviewed = [];

  /// Live `@…` autocomplete state (Phase 2.5). Non-null [_mentionQuery] means
  /// the caret is inside a mention being typed, and [_mentionMatches] holds
  /// the profiles offered for it.
  MentionQuery? _mentionQuery;
  List<ProfileEntry> _mentionMatches = const [];
  int _mentionHighlighted = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _controller.addListener(_onChanged);
    _titleController.addListener(_onChanged);
    // Intercept keys at the field's own node: an ancestor Focus would never
    // see Enter or the arrows, since the text field consumes them first.
    _focusNode.onKeyEvent = _handleEditorKey;
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
      _wordsAtLastSnapshot = doc.wordCount;
    });
    // Setting .text fires the change listener; reset dirty afterwards.
    _controller.text = doc.content;
    _titleController.text = doc.title;
    _dirty = false;
    _publishMentions();
  }

  /// Tells the Reference Panel which profiles this scene mentions. Runs on
  /// load and on the save debounce rather than per keystroke — the panel
  /// should settle when you pause, not flicker as you type a name.
  void _publishMentions() {
    final names = extractMentions(_controller.text);
    final current = ref.read(sceneMentionedNamesProvider);
    if (names.length == current.length &&
        List.generate(names.length, (i) => names[i] == current[i]).every((x) => x)) {
      return; // unchanged — avoid needless panel rebuilds
    }
    ref.read(sceneMentionedNamesProvider.notifier).state = names;
  }

  void _onChanged() {
    if (_doc == null) return;
    _dirty = true;
    final count = _countWords(_controller.text);
    if (count != _wordCount) setState(() => _wordCount = count);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 1), _flushSave);
    _updateMentionAutocomplete();

    // PLAN.md: auto snapshot after ~30s of no typing, or ~300 words
    // changed, whichever comes first.
    if ((count - _wordsAtLastSnapshot).abs() >= 300) {
      _snapshotDebounce?.cancel();
      _recordAutoSnapshot();
    } else {
      _snapshotDebounce?.cancel();
      _snapshotDebounce = Timer(const Duration(seconds: 30), _recordAutoSnapshot);
    }
  }

  Future<void> _recordAutoSnapshot() async {
    final history = await ref.read(sceneHistoryServiceProvider(widget.project).future);
    await history.recordAutoSnapshot(widget.contentId, _controller.text);
    if (!mounted) return;
    _wordsAtLastSnapshot = _countWords(_controller.text);
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
    if (mounted) _publishMentions();
  }

  // ---- @mention autocomplete -------------------------------------------

  /// Recomputes the autocomplete list from the text before the caret. Matches
  /// are prefix-first then substring, so typing "el" offers Elena before
  /// Michael, with characters ahead of world entries.
  void _updateMentionAutocomplete() {
    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _closeMentionAutocomplete();
      return;
    }

    final query = mentionQueryAt(_controller.text, selection.baseOffset);
    if (query == null) {
      _closeMentionAutocomplete();
      return;
    }

    final characters =
        ref.read(characterListProvider(widget.project)).valueOrNull ?? const [];
    final world = ref.read(worldListProvider(widget.project)).valueOrNull ?? const [];
    final lower = query.query.trim().toLowerCase();

    final candidates = [...characters, ...world];
    final matches = lower.isEmpty
        ? candidates
        : [
            ...candidates.where((e) => e.name.toLowerCase().startsWith(lower)),
            ...candidates.where((e) =>
                !e.name.toLowerCase().startsWith(lower) &&
                e.name.toLowerCase().contains(lower)),
          ];

    setState(() {
      _mentionQuery = query;
      _mentionMatches = matches.take(6).toList();
      _mentionHighlighted = 0;
    });
  }

  void _closeMentionAutocomplete() {
    if (_mentionQuery == null && _mentionMatches.isEmpty) return;
    setState(() {
      _mentionQuery = null;
      _mentionMatches = const [];
      _mentionHighlighted = 0;
    });
  }

  /// Replaces the typed `@query` with `[[Name]] `, leaving the caret after it.
  void _insertMention(ProfileEntry entry) {
    final query = _mentionQuery;
    if (query == null) return;

    final text = _controller.text;
    final caret = _controller.selection.baseOffset;
    final insertion = '[[${entry.name}]] ';

    _controller.value = TextEditingValue(
      text: text.replaceRange(query.start, caret, insertion),
      selection: TextSelection.collapsed(offset: query.start + insertion.length),
    );
    _closeMentionAutocomplete();
    _publishMentions();
    _focusNode.requestFocus();
  }

  /// Arrow keys and Enter/Tab drive the popup while it's open; Esc dismisses
  /// it. Everything else falls through to normal typing.
  KeyEventResult _handleEditorKey(FocusNode node, KeyEvent event) {
    if (_mentionQuery == null || _mentionMatches.isEmpty) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        setState(() =>
            _mentionHighlighted = (_mentionHighlighted + 1) % _mentionMatches.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        setState(() => _mentionHighlighted =
            (_mentionHighlighted - 1 + _mentionMatches.length) % _mentionMatches.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.tab:
        _insertMention(_mentionMatches[_mentionHighlighted]);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _closeMentionAutocomplete();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  void dispose() {
    _flushSave();
    _saveDebounce?.cancel();
    _snapshotDebounce?.cancel();
    _dictationEngine?.dispose();
    _controller.dispose();
    _titleController.dispose();
    _undoController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---- dictation -------------------------------------------------------

  Future<void> _toggleDictation() async {
    if (_dictationBusy) return;
    if (_isDictating) {
      await _stopDictation();
      return;
    }

    setState(() => _dictationBusy = true);
    try {
      final ready = await ensureDictationModelReady(context, ref);
      if (!ready) return;

      _dictationEngine ??= await ref.read(dictationEngineProvider.future);
      await _dictationEngine!.start(_handleDictationResult);
      if (!mounted) return;
      setState(() => _isDictating = true);
      ref.read(isDictatingProvider.notifier).state = true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Dictation failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _dictationBusy = false);
    }
  }

  Future<void> _stopDictation() async {
    await _dictationEngine?.stop();
    if (!mounted) return;
    setState(() => _isDictating = false);
    ref.read(isDictatingProvider.notifier).state = false;
  }

  /// Only final (endpointed) chunks are inserted — partial/in-progress
  /// speech is shown by the engines for future use but not committed to the
  /// document, since a plain `TextField` has no clean way to show
  /// uncommitted preview text without it looking like a real edit.
  void _handleDictationResult(DictationResult result) {
    if (!result.isFinal || result.text.isEmpty) return;

    final processed = VoiceCommandProcessor.process(result.text);
    final sel = _controller.selection;
    final text = _controller.text;
    final insertAt = sel.isValid ? sel.start : text.length;
    final needsLeadingSpace =
        insertAt > 0 && text[insertAt - 1] != '\n' && text[insertAt - 1] != ' ';
    final insertion = '${needsLeadingSpace ? ' ' : ''}$processed';

    _controller.value = TextEditingValue(
      text: text.replaceRange(insertAt, sel.isValid ? sel.end : insertAt, insertion),
      selection: TextSelection.collapsed(offset: insertAt + insertion.length),
    );

    setState(() {
      _unreviewed = [..._unreviewed, (insertAt, insertAt + insertion.length)];
    });
  }

  void _reviewNextDictatedRange() {
    if (_unreviewed.isEmpty) return;
    final (start, end) = _unreviewed.first;
    final safeEnd = end.clamp(0, _controller.text.length);
    final safeStart = start.clamp(0, safeEnd);
    _controller.selection = TextSelection(baseOffset: safeStart, extentOffset: safeEnd);
    _focusNode.requestFocus();
    setState(() => _unreviewed = _unreviewed.skip(1).toList());
  }

  // ---- version history -------------------------------------------------

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SceneHistoryScreen(
          project: widget.project,
          sceneId: widget.contentId,
          sceneTitle: _titleController.text.trim().isEmpty
              ? widget.fallbackTitle
              : _titleController.text.trim(),
          onRestored: (restoredContent) {
            _controller.text = restoredContent;
            _flushSave();
          },
        ),
      ),
    );
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
                IconButton(
                  tooltip: 'Version History',
                  icon: const Icon(Icons.history),
                  onPressed: _openHistory,
                ),
                const VerticalDivider(width: 16),
                IconButton(
                  tooltip: _isDictating ? 'Stop dictation' : 'Start dictation',
                  icon: _dictationBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_isDictating ? Icons.mic : Icons.mic_none),
                  color: _isDictating ? Theme.of(context).colorScheme.error : null,
                  onPressed: _dictationBusy ? null : _toggleDictation,
                ),
                if (_unreviewed.isNotEmpty)
                  ActionChip(
                    avatar: const Icon(Icons.fact_check_outlined, size: 16),
                    label: Text('Review ${_unreviewed.length} dictated'),
                    onPressed: _reviewNextDictatedRange,
                  ),
                const Spacer(),
                Text('$_wordCount words',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(width: 8),
              ],
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: focusMode ? 96 : 24),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  undoController: _undoController,
                  style: textStyle,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  onTap: _closeMentionAutocomplete,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Start writing…',
                  ),
                ),
              ),
              if (_mentionQuery != null && _mentionMatches.isNotEmpty)
                Positioned(
                  left: focusMode ? 96 : 24,
                  top: 8,
                  child: _MentionSuggestions(
                    matches: _mentionMatches,
                    highlighted: _mentionHighlighted,
                    onSelected: _insertMention,
                  ),
                ),
            ],
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

/// Floating list of profiles matching the `@` query being typed.
///
/// Anchored to the top of the editor area rather than to the caret: caret
/// anchoring needs TextPainter geometry that has to be tuned by eye against a
/// running window, and a popup in a predictable place beats one that lands
/// slightly wrong. Worth revisiting once the rich-text editor lands.
class _MentionSuggestions extends StatelessWidget {
  const _MentionSuggestions({
    required this.matches,
    required this.highlighted,
    required this.onSelected,
  });

  final List<ProfileEntry> matches;
  final int highlighted;
  final ValueChanged<ProfileEntry> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, entry) in matches.indexed)
              ListTile(
                dense: true,
                selected: index == highlighted,
                leading: Icon(
                  entry.id.startsWith('char-') ? Icons.person_outline : Icons.public,
                  size: 18,
                ),
                title: Text(entry.name, overflow: TextOverflow.ellipsis),
                subtitle: entry.category == null ? null : Text(entry.category!),
                onTap: () => onSelected(entry),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text(
                '↑↓ to choose · Enter to insert · Esc to dismiss',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
