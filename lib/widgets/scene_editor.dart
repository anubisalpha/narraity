import 'dart:async';

import 'package:flutter/material.dart';
// Flutter's own services.dart exports a SpellCheckService too (its native
// platform spellcheck integration) — hidden since this app has its own,
// Hunspell-backed one (../services/spell_check_service.dart).
import 'package:flutter/services.dart' hide SpellCheckService;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/annotation.dart';
import '../models/content_owner.dart';
import '../models/manuscript.dart';
import '../models/profile_entry.dart';
import '../models/project.dart';
import '../screens/scene_history_screen.dart';
import '../services/dictation_engine.dart';
import '../services/manuscript_service.dart';
import '../services/mention_scanner.dart';
import '../services/spell_check_service.dart';
import '../services/thesaurus_service.dart';
import '../services/tts_service.dart';
import '../services/voice_command_processor.dart';
import '../state/annotation_provider.dart';
import '../state/dictation_provider.dart';
import '../state/editor_settings_provider.dart';
import '../state/manuscript_provider.dart';
import '../state/reference_panel_provider.dart'
    show ReferenceCardItem, sceneMentionedNamesProvider;
import '../state/reference_provider.dart';
import '../state/scene_history_provider.dart';
import '../state/spell_check_provider.dart';
import '../state/thesaurus_provider.dart';
import '../state/tts_provider.dart';
import '../state/tts_settings_provider.dart';
import 'annotation_highlight_controller.dart';
import 'annotation_panel.dart';
import 'dictation_model_dialog.dart';
import 'spelling_panel.dart';

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

/// Menu entries for the single consolidated annotations toolbar button.
enum _AnnotationAction {
  highlightYellow,
  highlightGreen,
  highlightPink,
  highlightBlue,
  comment,
  stickyNote,
  footnote,
  togglePanel,
}

class _SceneEditorState extends ConsumerState<SceneEditor> {
  final _controller = AnnotationHighlightController();
  final _titleController = TextEditingController();
  final _undoController = UndoHistoryController();
  final _focusNode = FocusNode();

  bool _annotationsPanelOpen = false;
  bool _spellingPanelOpen = false;

  SceneDoc? _doc;
  Timer? _saveDebounce;
  bool _dirty = false;
  int _wordCount = 0;
  String? _lastChangedText;

  Timer? _snapshotDebounce;
  int _wordsAtLastSnapshot = 0;

  DictationEngine? _dictationEngine;
  bool _isDictating = false;
  bool _dictationBusy = false;
  List<(int start, int end)> _unreviewed = [];

  // Lazily created only when Read Aloud is actually used (not cached in
  // initState) — every SceneEditor mount would otherwise create the
  // platform plugin just to satisfy the cache, and its eventual disposal
  // unconditionally calls `stop()`, which throws `MissingPluginException`
  // in a test environment with no `flutter_tts` mock, even for tests that
  // never touch Read Aloud at all.
  TtsService? _tts;
  bool _isReadingAloud = false;
  int? _readingStart;
  bool _disposed = false;

  Timer? _spellCheckDebounce;
  List<(int start, int end)> _misspelled = [];
  // Set once if the dictionary fails to load (e.g. a test environment with
  // no path_provider mock) so repeated debounce ticks don't keep retrying a
  // load that's already known to fail — spell check just stays off rather
  // than breaking the rest of the editor.
  bool _spellCheckUnavailable = false;
  bool _spellCheckRunning = false;
  // Bumped on every run so a scan that's still yielding through a long
  // document (see findMisspelledAsync) can tell it's been superseded by a
  // newer one (the user kept typing, or switched scenes) and discard its
  // now-stale result instead of clobbering the current one.
  int _spellCheckGeneration = 0;

  /// Live `@…` autocomplete state (Phase 2.5). Non-null [_mentionQuery] means
  /// the caret is inside a mention being typed, and [_mentionMatches] holds
  /// the profiles offered for it.
  MentionQuery? _mentionQuery;
  List<ReferenceCardItem> _mentionMatches = const [];
  int _mentionHighlighted = 0;

  /// Thesaurus popover state (Phase 4.5): non-null [_thesaurusWord] means the
  /// popover is open, showing synonyms/definitions for the word selected via
  /// the "Look Up" entry added to the text field's own selection toolbar.
  String? _thesaurusWord;
  (int start, int end)? _thesaurusRange;
  List<WordSense> _thesaurusSenses = const [];
  bool _thesaurusLoading = false;

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
      _stopReading();
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
    await _resolveAnnotations();
    // Deferred a frame: the *first* spell check of a session also loads the
    // spell check service (dictionary extraction + native Hunspell init),
    // which is one-time work heavy enough to starve this same isolate from
    // painting the document it's attached to — the scene would sit on its
    // own loading spinner behind the block instead of showing content
    // immediately, exactly the freeze findMisspelledAsync's chunking can't
    // help with since it happens before that method is ever reached.
    // Posting this past the current frame lets the doc render first; the
    // spell check indicator then covers the (still slow, just no longer
    // blocking) service load once content is already on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleSpellCheck(immediate: true);
    });
  }

  // ---- spell check (Phase 4.5) -------------------------------------------

  void _scheduleSpellCheck({bool immediate = false}) {
    if (_spellCheckUnavailable || !ref.read(spellCheckEnabledProvider)) return;
    _spellCheckDebounce?.cancel();
    if (immediate) {
      _runSpellCheck();
    } else {
      _spellCheckDebounce = Timer(const Duration(milliseconds: 400), _runSpellCheck);
    }
  }

  Future<void> _runSpellCheck() async {
    final generation = ++_spellCheckGeneration;
    // Set before awaiting the service too — on a session's first check this
    // wait includes one-time dictionary extraction and native Hunspell
    // init, not just the scan itself, and that's the slower part.
    setState(() => _spellCheckRunning = true);

    final SpellCheckService service;
    try {
      service = await ref.read(spellCheckServiceProvider.future);
    } catch (_) {
      // Dictionary unavailable (missing asset, no path_provider in a test
      // environment, ...) — spell check just stays off rather than
      // breaking the rest of the editor, and stop retrying every debounce.
      _spellCheckUnavailable = true;
      if (mounted) setState(() => _spellCheckRunning = false);
      return;
    }
    if (_disposed || generation != _spellCheckGeneration) return;
    final ranges = await service.findMisspelledAsync(_controller.text);
    if (_disposed || generation != _spellCheckGeneration) return;
    _controller.misspelledRanges = ranges;
    setState(() {
      _misspelled = ranges;
      _spellCheckRunning = false;
    });
  }

  void _jumpToMisspelled(int start, int end) {
    final safeEnd = end.clamp(0, _controller.text.length);
    final safeStart = start.clamp(0, safeEnd);
    _controller.selection = TextSelection(baseOffset: safeStart, extentOffset: safeEnd);
    _focusNode.requestFocus();
  }

  /// Replaces the `[start, end)` character range with [replacement] and
  /// leaves the caret just after it. Shared by the spelling panel's
  /// suggestion chips and the thesaurus popover's synonym chips — both are
  /// "swap this range for a different word" in the same editor.
  void _replaceRange(int start, int end, String replacement) {
    final text = _controller.text;
    final safeEnd = end.clamp(0, text.length);
    final safeStart = start.clamp(0, safeEnd);
    _controller.value = TextEditingValue(
      text: text.replaceRange(safeStart, safeEnd, replacement),
      selection: TextSelection.collapsed(offset: safeStart + replacement.length),
    );
    _focusNode.requestFocus();
  }

  Future<void> _addToDictionary(String word) async {
    final service = await ref.read(spellCheckServiceProvider.future);
    await service.addToSessionDictionary(word);
    if (_disposed) return;
    _scheduleSpellCheck(immediate: true);
  }

  // ---- annotations (Phase 4: comments, highlights, sticky notes, footnotes) --

  /// Re-locates this scene's annotations against the loaded content (self-
  /// healing any offsets that only moved), feeds the result to the
  /// highlight-painting controller, and refreshes the panel's list.
  Future<void> _resolveAnnotations() async {
    final service = await ref.read(
      annotationServiceProvider(widget.project).future,
    );
    final results = await service.resolveForScene(
      widget.contentId,
      _controller.text,
    );
    if (!mounted) return;
    _controller.annotations = results;
    ref.invalidate(
      sceneAnnotationsProvider((widget.project, widget.contentId)),
    );
  }

  Future<String?> _promptForText(String title, String label) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _requireSelection() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Select some text first')));
  }

  Future<void> _handleAnnotationAction(_AnnotationAction action) async {
    switch (action) {
      case _AnnotationAction.highlightYellow:
        await _addHighlight(0xFFFFF59D);
      case _AnnotationAction.highlightGreen:
        await _addHighlight(0xFFA5D6A7);
      case _AnnotationAction.highlightPink:
        await _addHighlight(0xFFF48FB1);
      case _AnnotationAction.highlightBlue:
        await _addHighlight(0xFF90CAF9);
      case _AnnotationAction.comment:
        await _addComment();
      case _AnnotationAction.stickyNote:
        await _addStickyNote();
      case _AnnotationAction.footnote:
        await _addFootnote();
      case _AnnotationAction.togglePanel:
        setState(() => _annotationsPanelOpen = !_annotationsPanelOpen);
    }
  }

  Future<void> _addHighlight(int color) async {
    final sel = _controller.selection;
    if (!sel.isValid || sel.isCollapsed) {
      _requireSelection();
      return;
    }
    final quoted = sel.textInside(_controller.text);
    final service = await ref.read(
      annotationServiceProvider(widget.project).future,
    );
    await service.create(
      sceneId: widget.contentId,
      kind: AnnotationKind.highlight,
      anchor: TextAnchor(start: sel.start, end: sel.end, quotedText: quoted),
      color: color,
    );
    await _resolveAnnotations();
  }

  Future<void> _addComment() async {
    final sel = _controller.selection;
    if (!sel.isValid || sel.isCollapsed) {
      _requireSelection();
      return;
    }
    final body = await _promptForText('Add Comment', 'Comment');
    if (body == null || body.trim().isEmpty) return;
    final quoted = sel.textInside(_controller.text);
    final service = await ref.read(
      annotationServiceProvider(widget.project).future,
    );
    await service.create(
      sceneId: widget.contentId,
      kind: AnnotationKind.comment,
      anchor: TextAnchor(start: sel.start, end: sel.end, quotedText: quoted),
      body: body.trim(),
    );
    await _resolveAnnotations();
  }

  Future<void> _addStickyNote() async {
    final sel = _controller.selection;
    if (!sel.isValid || sel.isCollapsed) {
      _requireSelection();
      return;
    }
    final body = await _promptForText('Add Sticky Note', 'Note');
    if (body == null || body.trim().isEmpty) return;
    final quoted = sel.textInside(_controller.text);
    final service = await ref.read(
      annotationServiceProvider(widget.project).future,
    );
    await service.create(
      sceneId: widget.contentId,
      kind: AnnotationKind.stickyNote,
      anchor: TextAnchor(start: sel.start, end: sel.end, quotedText: quoted),
      body: body.trim(),
    );
    await _resolveAnnotations();
  }

  /// Footnotes anchor to a single point, not a range — the caret if there's
  /// no selection, or the end of the selection if there is one.
  Future<void> _addFootnote() async {
    final sel = _controller.selection;
    if (!sel.isValid) {
      // A controller that's never been focused/tapped has an invalid
      // selection (no caret placed yet) — silently no-op'ing here was the
      // actual "footnote button does nothing" bug: give the same kind of
      // feedback the other three actions already give on a bad selection.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Click in the text where you want the footnote first'),
        ),
      );
      return;
    }
    final body = await _promptForText('Add Footnote', 'Footnote text');
    if (body == null || body.trim().isEmpty) return;
    final at = sel.isCollapsed ? sel.baseOffset : sel.end;
    final service = await ref.read(
      annotationServiceProvider(widget.project).future,
    );
    await service.create(
      sceneId: widget.contentId,
      kind: AnnotationKind.footnote,
      anchor: TextAnchor(start: at, end: at, quotedText: ''),
      body: body.trim(),
    );
    await _resolveAnnotations();
  }

  /// Selects an annotation's current (possibly self-healed) range in the
  /// editor and focuses it — the panel's "jump to" action.
  void _jumpToAnnotation(Annotation annotation) {
    var start = annotation.anchor.start;
    var end = annotation.anchor.end;
    for (final (candidate, resolution) in _controller.annotations) {
      if (candidate.id == annotation.id) {
        start = resolution.start;
        end = resolution.end;
        break;
      }
    }
    final safeEnd = end.clamp(0, _controller.text.length);
    final safeStart = start.clamp(0, safeEnd);
    _controller.selection = TextSelection(
      baseOffset: safeStart,
      extentOffset: safeEnd,
    );
    _focusNode.requestFocus();
  }

  /// Tells the Reference Panel which profiles this scene mentions. Runs on
  /// load and on the save debounce rather than per keystroke — the panel
  /// should settle when you pause, not flicker as you type a name.
  void _publishMentions() {
    final names = extractMentions(_controller.text);
    final current = ref.read(sceneMentionedNamesProvider);
    if (names.length == current.length &&
        List.generate(
          names.length,
          (i) => names[i] == current[i],
        ).every((x) => x)) {
      return; // unchanged — avoid needless panel rebuilds
    }
    ref.read(sceneMentionedNamesProvider.notifier).state = names;
  }

  void _onChanged() {
    if (_doc == null) return;
    _updateMentionAutocomplete();

    // The controller also notifies listeners for annotation/speaking-range
    // updates that don't touch text or selection (see
    // AnnotationHighlightController) — Read Aloud pings this on every word
    // boundary, many times a second. Without this guard the save debounce
    // would keep resetting for as long as reading continues, delaying
    // autosave until speech stops instead of ~1s after the last real edit.
    final text = _controller.text;
    if (text == _lastChangedText) return;
    _lastChangedText = text;

    // A real edit invalidates the reading position (offsets after the edit
    // point shift) — stop rather than keep speaking against stale offsets.
    if (_isReadingAloud) _stopReading();
    _scheduleSpellCheck();

    _dirty = true;
    final count = _countWords(text);
    if (count != _wordCount) setState(() => _wordCount = count);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 1), _flushSave);

    // PLAN.md: auto snapshot after ~30s of no typing, or ~300 words
    // changed, whichever comes first.
    if ((count - _wordsAtLastSnapshot).abs() >= 300) {
      _snapshotDebounce?.cancel();
      _recordAutoSnapshot();
    } else {
      _snapshotDebounce?.cancel();
      _snapshotDebounce = Timer(
        const Duration(seconds: 30),
        _recordAutoSnapshot,
      );
    }
  }

  Future<void> _recordAutoSnapshot() async {
    final history = await ref.read(
      sceneHistoryServiceProvider(widget.project).future,
    );
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

  // ---- thesaurus (Phase 4.5) ---------------------------------------------

  Future<void> _lookUpWord(String word, int start, int end) async {
    setState(() {
      _thesaurusWord = word;
      _thesaurusRange = (start, end);
      _thesaurusSenses = const [];
      _thesaurusLoading = true;
    });
    final ThesaurusService service;
    try {
      service = await ref.read(thesaurusServiceProvider.future);
    } catch (_) {
      // Dataset unavailable (missing asset, no path_provider in a test
      // environment, ...) — the popover just shows "no entry" rather than
      // breaking the rest of the editor, same shape as spell check.
      if (mounted) setState(() => _thesaurusLoading = false);
      return;
    }
    if (_disposed) return;
    final senses = service.lookup(word);
    if (!mounted) return;
    setState(() {
      _thesaurusSenses = senses;
      _thesaurusLoading = false;
    });
  }

  void _closeThesaurusPopover() {
    setState(() {
      _thesaurusWord = null;
      _thesaurusRange = null;
      _thesaurusSenses = const [];
    });
  }

  void _replaceWithSynonym(String synonym) {
    final range = _thesaurusRange;
    if (range == null) return;
    final (start, end) = range;
    _replaceRange(start, end, synonym);
    _closeThesaurusPopover();
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

    final owner = ContentOwner.project(widget.project);
    final characters = ref.read(characterListProvider(owner)).valueOrNull ?? const [];
    final world = ref.read(worldListProvider(owner)).valueOrNull ?? const [];
    final lower = query.query.trim().toLowerCase();

    final candidates = [
      for (final entry in characters)
        ReferenceCardItem(entry, ProfileKind.character),
      for (final entry in world) ReferenceCardItem(entry, ProfileKind.world),
    ];
    bool startsWithQuery(ReferenceCardItem item) =>
        item.entry.name.toLowerCase().startsWith(lower);

    final matches = lower.isEmpty
        ? candidates
        : [
            ...candidates.where(startsWithQuery),
            ...candidates.where(
              (item) =>
                  !startsWithQuery(item) &&
                  item.entry.name.toLowerCase().contains(lower),
            ),
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
  void _insertMention(ReferenceCardItem item) {
    final query = _mentionQuery;
    if (query == null) return;

    final text = _controller.text;
    final caret = _controller.selection.baseOffset;
    final insertion = '[[${item.entry.name}]] ';

    _controller.value = TextEditingValue(
      text: text.replaceRange(query.start, caret, insertion),
      selection: TextSelection.collapsed(
        offset: query.start + insertion.length,
      ),
    );
    _closeMentionAutocomplete();
    _publishMentions();
    _focusNode.requestFocus();
  }

  /// Arrow keys and Enter/Tab drive the popup while it's open; Esc dismisses
  /// it. Everything else falls through to normal typing.
  KeyEventResult _handleEditorKey(FocusNode node, KeyEvent event) {
    if (_mentionQuery == null || _mentionMatches.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        setState(
          () => _mentionHighlighted =
              (_mentionHighlighted + 1) % _mentionMatches.length,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        setState(
          () => _mentionHighlighted =
              (_mentionHighlighted - 1 + _mentionMatches.length) %
              _mentionMatches.length,
        );
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
    _disposed = true;
    if (_isReadingAloud) _tts?.stop(); // fire-and-forget; see _disposed guard below
    _flushSave();
    _saveDebounce?.cancel();
    _snapshotDebounce?.cancel();
    _spellCheckDebounce?.cancel();
    _dictationEngine?.dispose();
    _controller.dispose();
    _titleController.dispose();
    _undoController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---- read aloud --------------------------------------------------------

  Future<void> _toggleReadAloud() async {
    if (_isReadingAloud) {
      await _stopReading();
    } else {
      await _startReading();
    }
  }

  Future<void> _startReading() async {
    final text = _controller.text;
    final sel = _controller.selection;
    final start = (sel.isValid ? sel.start : 0).clamp(0, text.length);
    if (text.substring(start).trim().isEmpty) return;

    _tts ??= ref.read(ttsServiceProvider);
    final tts = _tts!;
    final settings = ref.read(ttsSettingsProvider);
    await tts.setSpeechRate(settings.rate);
    await tts.setPitch(settings.pitch);
    final voice = settings.voice;
    if (voice != null) await tts.setVoice(voice);

    _readingStart = start;
    setState(() => _isReadingAloud = true);
    ref.read(isReadingAloudProvider.notifier).state = true;

    await tts.speak(
      text.substring(start),
      onProgress: (progress) {
        if (_disposed) return;
        final base = _readingStart;
        if (base == null) return;
        _controller.speakingRange = (base + progress.start, base + progress.end);
      },
      onComplete: () {
        if (_disposed) return;
        _controller.speakingRange = null;
        _readingStart = null;
        setState(() => _isReadingAloud = false);
        ref.read(isReadingAloudProvider.notifier).state = false;
      },
    );
  }

  Future<void> _stopReading() async {
    if (!_isReadingAloud) return;
    await _tts?.stop();
    if (_disposed) return;
    _controller.speakingRange = null;
    _readingStart = null;
    setState(() => _isReadingAloud = false);
    ref.read(isReadingAloudProvider.notifier).state = false;
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Dictation failed: $error')));
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
      text: text.replaceRange(
        insertAt,
        sel.isValid ? sel.end : insertAt,
        insertion,
      ),
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
    _controller.selection = TextSelection(
      baseOffset: safeStart,
      extentOffset: safeEnd,
    );
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
    if (selected.startsWith(marker) &&
        selected.endsWith(marker) &&
        selected.length >= marker.length * 2) {
      replacement = selected.substring(
        marker.length,
        selected.length - marker.length,
      );
    } else {
      replacement = '$marker$selected$marker';
    }
    _controller.value = TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, replacement),
      selection: TextSelection.collapsed(
        offset:
            sel.start + (selected.isEmpty ? marker.length : replacement.length),
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
            onPressed: () => Navigator.of(
              context,
            ).pop((findController.text, replaceController.text, false)),
            child: const Text('Replace first'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              context,
            ).pop((findController.text, replaceController.text, true)),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('"$find" not found')));
      }
      return;
    }
    _controller.text = all
        ? text.replaceAll(find, replace)
        : text.replaceFirst(find, replace);
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
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    // A plain unwrapped Row here already overflowed once
                    // (five annotation icons pushed the panel-toggle button
                    // and this row's own trailing content off the visible
                    // edge, silently, since Release builds compile out the
                    // debug overflow warning). Scrolling instead of growing
                    // forever is the fix that survives future additions.
                    // IconButtonTheme tightens every button's default 48x48
                    // tap-target padding at once, rather than repeating
                    // padding/constraints props on ~15 individual buttons.
                    child: IconButtonTheme(
                      data: IconButtonThemeData(
                        style: IconButton.styleFrom(
                          minimumSize: const Size(36, 36),
                          padding: const EdgeInsets.all(4),
                        ),
                      ),
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
                            builder: (context, value, _) => Row(
                              children: [
                                IconButton(
                                  tooltip: 'Undo (Ctrl+Z)',
                                  icon: const Icon(Icons.undo),
                                  onPressed: value.canUndo
                                      ? _undoController.undo
                                      : null,
                                ),
                                IconButton(
                                  tooltip: 'Redo (Ctrl+Y)',
                                  icon: const Icon(Icons.redo),
                                  onPressed: value.canRedo
                                      ? _undoController.redo
                                      : null,
                                ),
                              ],
                            ),
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
                            tooltip: _isDictating
                                ? 'Stop dictation'
                                : 'Start dictation',
                            icon: _dictationBusy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _isDictating ? Icons.mic : Icons.mic_none,
                                  ),
                            color: _isDictating
                                ? Theme.of(context).colorScheme.error
                                : null,
                            onPressed: _dictationBusy ? null : _toggleDictation,
                          ),
                          const VerticalDivider(width: 16),
                          IconButton(
                            tooltip: _isReadingAloud ? 'Stop reading' : 'Read Aloud',
                            icon: Icon(
                              _isReadingAloud ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
                            ),
                            color: _isReadingAloud ? Theme.of(context).colorScheme.error : null,
                            onPressed: _toggleReadAloud,
                          ),
                          const VerticalDivider(width: 16),
                          IconButton(
                            tooltip: _spellCheckRunning
                                ? 'Checking spelling…'
                                : _misspelled.isEmpty
                                    ? 'Spelling'
                                    : 'Spelling (${_misspelled.length})',
                            icon: _spellCheckRunning
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Badge(
                                    label: Text('${_misspelled.length}'),
                                    isLabelVisible: _misspelled.isNotEmpty,
                                    child: const Icon(Icons.spellcheck),
                                  ),
                            onPressed: () =>
                                setState(() => _spellingPanelOpen = !_spellingPanelOpen),
                          ),
                          if (_unreviewed.isNotEmpty)
                            ActionChip(
                              avatar: const Icon(
                                Icons.fact_check_outlined,
                                size: 16,
                              ),
                              label: Text(
                                'Review ${_unreviewed.length} dictated',
                              ),
                              onPressed: _reviewNextDictatedRange,
                            ),
                          const VerticalDivider(width: 16),
                          // One button, not five: five separate IconButtons here
                          // overflowed the toolbar Row (which has no scroll/wrap) at
                          // ordinary window widths — a Release build swallows that
                          // overflow silently (the debug overflow-stripe painter is
                          // wrapped in an `assert`, stripped in Release), so the
                          // trailing icons just vanished with no visible error.
                          PopupMenuButton<_AnnotationAction>(
                            tooltip:
                                'Comments, highlights, sticky notes, footnotes',
                            icon: const Icon(Icons.chat_bubble_outline),
                            onSelected: _handleAnnotationAction,
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                enabled: false,
                                child: Text('Highlight selection'),
                              ),
                              for (final swatch in const [
                                (
                                  _AnnotationAction.highlightYellow,
                                  0xFFFFF59D,
                                  'Yellow',
                                ),
                                (
                                  _AnnotationAction.highlightGreen,
                                  0xFFA5D6A7,
                                  'Green',
                                ),
                                (
                                  _AnnotationAction.highlightPink,
                                  0xFFF48FB1,
                                  'Pink',
                                ),
                                (
                                  _AnnotationAction.highlightBlue,
                                  0xFF90CAF9,
                                  'Blue',
                                ),
                              ])
                                PopupMenuItem(
                                  value: swatch.$1,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 16,
                                        height: 16,
                                        color: Color(swatch.$2),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(swatch.$3),
                                    ],
                                  ),
                                ),
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: _AnnotationAction.comment,
                                child: ListTile(
                                  leading: Icon(Icons.comment_outlined),
                                  title: Text('Add Comment'),
                                ),
                              ),
                              const PopupMenuItem(
                                value: _AnnotationAction.stickyNote,
                                child: ListTile(
                                  leading: Icon(Icons.sticky_note_2_outlined),
                                  title: Text('Add Sticky Note'),
                                ),
                              ),
                              const PopupMenuItem(
                                value: _AnnotationAction.footnote,
                                child: ListTile(
                                  leading: Icon(Icons.note_alt_outlined),
                                  title: Text('Add Footnote'),
                                ),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: _AnnotationAction.togglePanel,
                                child: ListTile(
                                  leading: Icon(
                                    _annotationsPanelOpen
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                  ),
                                  title: Text(
                                    _annotationsPanelOpen
                                        ? 'Hide Annotations'
                                        : 'Show Annotations',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Text(
                  '$_wordCount words',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
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
                  contextMenuBuilder: (context, editableTextState) {
                    final selection = editableTextState.textEditingValue.selection;
                    final buttonItems = editableTextState.contextMenuButtonItems.toList();
                    if (selection.isValid &&
                        !selection.isCollapsed &&
                        ref.read(thesaurusEnabledProvider)) {
                      final selected = selection
                          .textInside(editableTextState.textEditingValue.text)
                          .trim();
                      if (selected.isNotEmpty && !selected.contains(RegExp(r'\s'))) {
                        buttonItems.insert(
                          0,
                          ContextMenuButtonItem(
                            label: 'Look Up "$selected"',
                            onPressed: () {
                              editableTextState.hideToolbar();
                              _lookUpWord(selected, selection.start, selection.end);
                            },
                          ),
                        );
                      }
                    }
                    return AdaptiveTextSelectionToolbar.buttonItems(
                      anchors: editableTextState.contextMenuAnchors,
                      buttonItems: buttonItems,
                    );
                  },
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
              if (_thesaurusWord != null)
                Positioned(
                  right: 24,
                  top: 8,
                  child: _ThesaurusPopover(
                    word: _thesaurusWord!,
                    loading: _thesaurusLoading,
                    senses: _thesaurusSenses,
                    onSynonymSelected: _replaceWithSynonym,
                    onClose: _closeThesaurusPopover,
                  ),
                ),
            ],
          ),
        ),
        if (!focusMode && _annotationsPanelOpen) ...[
          const Divider(height: 1),
          AnnotationPanel(
            project: widget.project,
            sceneId: widget.contentId,
            onJumpTo: _jumpToAnnotation,
          ),
        ],
        if (!focusMode && _spellingPanelOpen) ...[
          const Divider(height: 1),
          SpellingPanel(
            content: _controller.text,
            misspelled: _misspelled,
            onJumpTo: _jumpToMisspelled,
            onReplace: _replaceRange,
            onAddToDictionary: _addToDictionary,
          ),
        ],
        if (focusMode)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '$_wordCount words',
              style: Theme.of(context).textTheme.labelSmall,
            ),
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

  final List<ReferenceCardItem> matches;
  final int highlighted;
  final ValueChanged<ReferenceCardItem> onSelected;

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
            for (final (index, item) in matches.indexed)
              ListTile(
                dense: true,
                selected: index == highlighted,
                leading: Icon(
                  item.kind == ProfileKind.character
                      ? Icons.person_outline
                      : Icons.public,
                  size: 18,
                ),
                title: Text(item.entry.name, overflow: TextOverflow.ellipsis),
                subtitle: item.entry.category == null
                    ? null
                    : Text(item.entry.category!),
                onTap: () => onSelected(item),
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

/// Synonyms/definitions for the word selected via the text field's own
/// "Look Up" context-menu entry (Phase 4.5). Anchored to a fixed corner of
/// the editor, not the selection itself — same pragmatic call as
/// [_MentionSuggestions]: precise caret/selection anchoring needs
/// `TextPainter` geometry tuned by eye against a running window.
class _ThesaurusPopover extends StatelessWidget {
  const _ThesaurusPopover({
    required this.word,
    required this.loading,
    required this.senses,
    required this.onSynonymSelected,
    required this.onClose,
  });

  final String word;
  final bool loading;
  final List<WordSense> senses;
  final ValueChanged<String> onSynonymSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320, maxHeight: 320),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(word, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: onClose,
                  ),
                ],
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (senses.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No thesaurus entry found.'),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final sense in senses)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '(${posLabel(sense.partOfSpeech)}) ${sense.definition}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (sense.synonyms.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      for (final synonym in sense.synonyms.take(8))
                                        ActionChip(
                                          label: Text(synonym),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => onSynonymSelected(synonym),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
