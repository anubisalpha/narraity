import 'dart:ffi';

import 'hunspell_ffi.dart';
import 'spellcheck_dictionary_service.dart';
import 'word_tokenizer.dart';

/// One loaded Hunspell dictionary (currently always `en_GB`, per PLAN.md's
/// "en-GB as the default" — additional languages/variants are a follow-up,
/// not built this session). Owns the native handle; call [dispose] when
/// done with it.
class SpellCheckService {
  SpellCheckService._(this._ffi, this._handle);

  final HunspellFfi _ffi;
  final Pointer<Void> _handle;

  static Future<SpellCheckService> load(
    String languageTag, {
    SpellCheckDictionaryService? dictionaryService,
  }) async {
    final ffi = HunspellFfi.instance();
    final dictionaries = dictionaryService ?? SpellCheckDictionaryService();
    final (affPath, dicPath) = await dictionaries.ensureExtracted(languageTag);
    final handle = ffi.create(affPath, dicPath);
    return SpellCheckService._(ffi, handle);
  }

  bool isCorrect(String word) => _ffi.spell(_handle, word);

  List<String> suggestionsFor(String word) => _ffi.suggest(_handle, word);

  /// Adds [word] to this session's run-time dictionary — not persisted
  /// across app restarts by Hunspell itself.
  void addToSessionDictionary(String word) => _ffi.addWord(_handle, word);

  /// Scans [content] and returns the `[start, end)` character range of
  /// every misspelled word, in document order.
  List<(int start, int end)> findMisspelled(String content) => [
        for (final word in tokenizeWords(content))
          if (!isCorrect(word.text)) (word.start, word.end),
      ];

  void dispose() => _ffi.destroy(_handle);
}
