import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/custom_dictionary_service.dart';
import 'package:narraity/services/library_service.dart';

void main() {
  late Directory tempDir;
  late CustomDictionaryService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_custom_dict_test_');
    service = CustomDictionaryService(libraryService: LibraryService(rootOverride: tempDir));
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('a language with no custom words yet returns an empty list', () async {
    expect(await service.loadWords('en_GB'), isEmpty);
  });

  test('addWord persists, and loadWords returns it back in insertion order', () async {
    await service.addWord('en_GB', 'Zqorbathil');
    await service.addWord('en_GB', 'Shamitz');

    expect(await service.loadWords('en_GB'), ['Zqorbathil', 'Shamitz']);
  });

  test('adding the same word twice does not duplicate it', () async {
    await service.addWord('en_GB', 'Zqorbathil');
    await service.addWord('en_GB', 'Zqorbathil');

    expect(await service.loadWords('en_GB'), ['Zqorbathil']);
  });

  test('words are scoped per language', () async {
    await service.addWord('en_GB', 'colour');
    await service.addWord('en_US', 'color');

    expect(await service.loadWords('en_GB'), ['colour']);
    expect(await service.loadWords('en_US'), ['color']);
  });

  test('a fresh CustomDictionaryService instance restores previously persisted words', () async {
    await service.addWord('en_GB', 'Zqorbathil');

    final reloaded =
        CustomDictionaryService(libraryService: LibraryService(rootOverride: tempDir));
    expect(await reloaded.loadWords('en_GB'), ['Zqorbathil']);
  });

  test('blank input is ignored', () async {
    await service.addWord('en_GB', '   ');
    expect(await service.loadWords('en_GB'), isEmpty);
  });

  test('removeWord drops just that word, and persists across a fresh instance', () async {
    await service.addWord('en_GB', 'Zqorbathil');
    await service.addWord('en_GB', 'Shamitz');

    await service.removeWord('en_GB', 'Zqorbathil');

    expect(await service.loadWords('en_GB'), ['Shamitz']);
    final reloaded =
        CustomDictionaryService(libraryService: LibraryService(rootOverride: tempDir));
    expect(await reloaded.loadWords('en_GB'), ['Shamitz']);
  });

  test('removeWord for a word that was never added is a no-op', () async {
    await service.addWord('en_GB', 'Shamitz');
    await service.removeWord('en_GB', 'NeverAdded');

    expect(await service.loadWords('en_GB'), ['Shamitz']);
  });
}
