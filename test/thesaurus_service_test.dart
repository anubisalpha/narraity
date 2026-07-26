import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/thesaurus_service.dart';
import 'package:narraity/services/wordnet_dictionary_service.dart';

// Real end-to-end coverage against the actual bundled wordnet.sqlite, same
// rationale as spell_check_service_test.dart: entirely offline and instant,
// no reason to fake it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ThesaurusService service;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('narraity_thesaurus_test_');
    service = await ThesaurusService.load(
      dictionaryService: WordnetDictionaryService(rootOverride: tempDir),
    );
  });

  tearDown(() {
    service.dispose();
    tempDir.deleteSync(recursive: true);
  });

  test('looks up synonyms and a definition for a common word', () {
    final senses = service.lookup('happy');
    expect(senses, isNotEmpty);
    expect(senses.first.definition, isNotEmpty);

    final allSynonyms = senses.expand((s) => s.synonyms).toSet();
    expect(allSynonyms, contains('felicitous'));
  });

  test('is case-insensitive and trims whitespace', () {
    final lower = service.lookup('happy');
    final upper = service.lookup('  Happy ');
    expect(upper.length, lower.length);
    expect(upper.first.definition, lower.first.definition);
  });

  test('excludes the queried word from its own synonym list', () {
    final senses = service.lookup('happy');
    for (final sense in senses) {
      expect(sense.synonyms, isNot(contains('happy')));
    }
  });

  test('returns multiple senses for a word with distinct meanings', () {
    final senses = service.lookup('bank');
    final distinctDefinitions = senses.map((s) => s.definition).toSet();
    expect(distinctDefinitions.length, greaterThan(1));
  });

  test('returns an empty list for a word not in the dataset', () {
    expect(service.lookup('zqxvvbnthisisnotaword'), isEmpty);
  });

  test('returns an empty list for empty/whitespace input', () {
    expect(service.lookup(''), isEmpty);
    expect(service.lookup('   '), isEmpty);
  });

  test('posLabel maps WordNet codes to readable labels', () {
    expect(posLabel('n'), 'noun');
    expect(posLabel('v'), 'verb');
    expect(posLabel('a'), 'adjective');
    expect(posLabel('s'), 'adjective');
    expect(posLabel('r'), 'adverb');
  });

  test('extraction is idempotent: loading twice reuses the extracted file',
      () async {
    final secondService = await ThesaurusService.load(
      dictionaryService: WordnetDictionaryService(rootOverride: tempDir),
    );
    expect(secondService.lookup('happy'), isNotEmpty);
    secondService.dispose();

    final dbFile = File('${tempDir.path}/wordnet.sqlite');
    expect(dbFile.existsSync(), isTrue);
  });
}
