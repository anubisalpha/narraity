import 'dart:ffi';

import 'custom_dictionary_service.dart';
import 'hunspell_ffi.dart';
import 'spellcheck_dictionary_service.dart';
import 'word_tokenizer.dart';

/// One loaded Hunspell dictionary (currently always `en_GB`, per PLAN.md's
/// "en-GB as the default" — additional languages/variants are a follow-up,
/// not built this session). Owns the native handle; call [dispose] when
/// done with it.
class SpellCheckService {
  SpellCheckService._(this._ffi, this._handle, this._customDictionary, this._languageTag);

  final HunspellFfi _ffi;
  final Pointer<Void> _handle;
  final CustomDictionaryService _customDictionary;
  final String _languageTag;

  static Future<SpellCheckService> load(
    String languageTag, {
    SpellCheckDictionaryService? dictionaryService,
    CustomDictionaryService? customDictionaryService,
  }) async {
    final ffi = HunspellFfi.instance();
    final dictionaries = dictionaryService ?? SpellCheckDictionaryService();
    final (affPath, dicPath) = await dictionaries.ensureExtracted(languageTag);
    final handle = ffi.create(affPath, dicPath);

    final customDictionary = customDictionaryService ?? CustomDictionaryService();
    // Replay every word a previous session added via "Add to Dictionary" —
    // Hunspell_add only ever touched the in-memory run-time dictionary, so
    // without this every custom word would need re-adding on every launch.
    for (final word in await customDictionary.loadWords(languageTag)) {
      ffi.addWord(handle, word);
    }

    return SpellCheckService._(ffi, handle, customDictionary, languageTag);
  }

  bool isCorrect(String word) => _ffi.spell(_handle, word);

  List<String> suggestionsFor(String word) => _ffi.suggest(_handle, word);

  /// Adds [word] to this session's run-time dictionary *and* persists it to
  /// `CustomDictionaryService`, so it's still recognized after an app
  /// restart, not just for the rest of this session.
  Future<void> addToSessionDictionary(String word) async {
    _ffi.addWord(_handle, word);
    await _customDictionary.addWord(_languageTag, word);
  }

  /// Every custom word currently persisted for this dictionary's language —
  /// what a "manage custom words" Settings list has to show.
  Future<List<String>> customWords() => _customDictionary.loadWords(_languageTag);

  /// Un-teaches [word] from both this session and the persisted list.
  Future<void> removeFromDictionary(String word) async {
    _ffi.removeWord(_handle, word);
    await _customDictionary.removeWord(_languageTag, word);
  }

  /// Scans [content] and returns the `[start, end)` character range of
  /// every misspelled word, in document order.
  List<(int start, int end)> findMisspelled(String content) => [
        for (final word in tokenizeWords(content))
          if (!isCorrect(word.text)) (word.start, word.end),
      ];

  /// Same result as [findMisspelled], but yields to the event loop every
  /// [chunkSize] words instead of checking the whole document in one
  /// unbroken synchronous pass. Each word check is a native Hunspell call,
  /// so a page with hundreds of misspellings (or just a long one) can add up
  /// to a stretch long enough to freeze the UI thread — this keeps the app
  /// responsive (and cancellable) while a scan is in flight, at the cost of
  /// the scan itself taking a little longer in wall-clock time.
  Future<List<(int start, int end)>> findMisspelledAsync(
    String content, {
    int chunkSize = 200,
  }) async {
    final result = <(int, int)>[];
    var sinceYield = 0;
    for (final word in tokenizeWords(content)) {
      if (!isCorrect(word.text)) result.add((word.start, word.end));
      if (++sinceYield >= chunkSize) {
        sinceYield = 0;
        await Future<void>.delayed(Duration.zero);
      }
    }
    return result;
  }

  void dispose() => _ffi.destroy(_handle);
}
