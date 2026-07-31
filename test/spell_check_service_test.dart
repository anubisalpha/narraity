import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/custom_dictionary_service.dart';
import 'package:narraity/services/library_service.dart';
import 'package:narraity/services/spell_check_service.dart';
import 'package:narraity/services/spellcheck_dictionary_service.dart';

// Real end-to-end coverage against the actual vendored libhunspell.dll and
// the actual bundled en_GB dictionary — unlike Vosk (network/binary-heavy),
// this is entirely offline and instant, so there's no reason to fake it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory libraryDir;
  late SpellCheckService service;

  CustomDictionaryService customDictionary() =>
      CustomDictionaryService(libraryService: LibraryService(rootOverride: libraryDir));

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('narraity_spellcheck_test_');
    libraryDir = Directory.systemTemp.createTempSync('narraity_spellcheck_lib_test_');
    service = await SpellCheckService.load(
      'en_GB',
      dictionaryService: SpellCheckDictionaryService(rootOverride: tempDir),
      customDictionaryService: customDictionary(),
    );
  });

  tearDown(() {
    service.dispose();
    tempDir.deleteSync(recursive: true);
    libraryDir.deleteSync(recursive: true);
  });

  test('recognizes correctly spelled British English words', () {
    expect(service.isCorrect('colour'), isTrue);
    expect(service.isCorrect('realise'), isTrue);
    expect(service.isCorrect('doorway'), isTrue);
  });

  test('flags a nonsense word as misspelled', () {
    expect(service.isCorrect('zxqvbfghw'), isFalse);
  });

  test('offers at least one suggestion for a common misspelling', () {
    final suggestions = service.suggestionsFor('recieve');
    expect(suggestions, isNotEmpty);
    expect(suggestions, contains('receive'));
  });

  test('adding a word to the session dictionary makes it recognized', () async {
    const madeUpName = 'Zqorbathil';
    expect(service.isCorrect(madeUpName), isFalse);

    await service.addToSessionDictionary(madeUpName);

    expect(service.isCorrect(madeUpName), isTrue);
  });

  test('a word added via addToSessionDictionary is still recognized after a fresh load — '
      'the actual bug being fixed (Hunspell_add alone only affects the in-memory session)',
      () async {
    const madeUpName = 'Zqorbathil';
    await service.addToSessionDictionary(madeUpName);

    final freshService = await SpellCheckService.load(
      'en_GB',
      dictionaryService: SpellCheckDictionaryService(rootOverride: tempDir),
      customDictionaryService: customDictionary(),
    );

    expect(freshService.isCorrect(madeUpName), isTrue);
    freshService.dispose();
  });

  test('customWords() lists what was added, in order', () async {
    await service.addToSessionDictionary('Zqorbathil');
    await service.addToSessionDictionary('Shamitz');

    expect(await service.customWords(), ['Zqorbathil', 'Shamitz']);
  });

  test('removeFromDictionary un-recognizes the word now, and it stays gone after a '
      'fresh load', () async {
    const madeUpName = 'Zqorbathil';
    await service.addToSessionDictionary(madeUpName);
    expect(service.isCorrect(madeUpName), isTrue);

    await service.removeFromDictionary(madeUpName);
    expect(service.isCorrect(madeUpName), isFalse);

    final freshService = await SpellCheckService.load(
      'en_GB',
      dictionaryService: SpellCheckDictionaryService(rootOverride: tempDir),
      customDictionaryService: customDictionary(),
    );
    expect(freshService.isCorrect(madeUpName), isFalse);
    freshService.dispose();
  });

  test('findMisspelled returns character ranges only for the bad words', () {
    const content = 'Elena stepped throuhg the zqxvvbn doorway.';
    final ranges = service.findMisspelled(content);

    final misspelledText = [
      for (final (start, end) in ranges) content.substring(start, end),
    ];
    expect(misspelledText, ['throuhg', 'zqxvvbn']);
  });

  test('extraction is idempotent: loading twice reuses the extracted files',
      () async {
    final secondService = await SpellCheckService.load(
      'en_GB',
      dictionaryService: SpellCheckDictionaryService(rootOverride: tempDir),
      customDictionaryService: customDictionary(),
    );
    expect(secondService.isCorrect('colour'), isTrue);
    secondService.dispose();

    // rootOverride substitutes for the whole "support/dictionaries" folder,
    // not just "support" — so the language subfolder sits directly under it.
    final affFile = File('${tempDir.path}/en_GB/en_GB.aff');
    final dicFile = File('${tempDir.path}/en_GB/en_GB.dic');
    expect(affFile.existsSync(), isTrue);
    expect(dicFile.existsSync(), isTrue);
  });
}
