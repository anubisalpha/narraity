import 'package:sqlite3/sqlite3.dart';

import 'wordnet_dictionary_service.dart';

/// One WordNet sense of a looked-up word: its part of speech, definition,
/// and any other words sharing that synset (its synonyms for this sense).
class WordSense {
  const WordSense({required this.partOfSpeech, required this.definition, required this.synonyms});

  final String partOfSpeech;
  final String definition;
  final List<String> synonyms;
}

/// Human-readable label for a WordNet part-of-speech code.
String posLabel(String code) => switch (code) {
      'n' => 'noun',
      'v' => 'verb',
      'a' => 'adjective',
      's' => 'adjective',
      'r' => 'adverb',
      _ => code,
    };

/// Synonym/definition lookups against the bundled Open English WordNet
/// database. Opened read-only — this is a static reference dataset, never
/// written to.
class ThesaurusService {
  ThesaurusService._(this._db);

  final Database _db;

  static Future<ThesaurusService> load({WordnetDictionaryService? dictionaryService}) async {
    final dictionaries = dictionaryService ?? WordnetDictionaryService();
    final path = await dictionaries.ensureExtracted();
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    return ThesaurusService._(db);
  }

  /// Returns every WordNet sense of [word], each with its synonyms (other
  /// members of that sense's synset, excluding [word] itself) and
  /// definition. Empty if the word isn't in the dataset.
  List<WordSense> lookup(String word) {
    final normalized = word.trim().toLowerCase();
    if (normalized.isEmpty) return const [];

    final rows = _db.select(
      '''
      SELECT s.pos, s.definition, s.members
      FROM senses se
      JOIN synsets s ON s.id = se.synset_id
      WHERE se.word = ?
      ''',
      [normalized],
    );

    return [
      for (final row in rows)
        WordSense(
          partOfSpeech: row['pos'] as String,
          definition: row['definition'] as String,
          synonyms: (row['members'] as String)
              .split('|')
              .where((m) => m.toLowerCase() != normalized)
              .toList(),
        ),
    ];
  }

  void dispose() => _db.dispose();
}
