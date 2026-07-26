// One-off build tool: compiles the Open English WordNet 2025 JSON dump into
// a compact SQLite database bundled as a Flutter asset (assets/wordnet/).
//
// Source data: https://github.com/globalwordnet/english-wordnet (OEWN 2025,
// CC BY 4.0). Download `english-wordnet-2025-json.zip` from the 2025-edition
// GitHub release and extract it to a folder, then run:
//
//   dart run tool/build_wordnet_db.dart <path-to-extracted-json-dir>
//
// This only needs to be re-run when picking up a newer OEWN release — the
// resulting wordnet.sqlite is committed to the repo like the Hunspell
// dictionaries, not rebuilt at app-build time.
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/build_wordnet_db.dart <extracted-json-dir>');
    exit(1);
  }
  final sourceDir = Directory(args[0]);
  if (!sourceDir.existsSync()) {
    stderr.writeln('Directory not found: ${sourceDir.path}');
    exit(1);
  }

  final outPath = 'assets/wordnet/wordnet.sqlite';
  File(outPath).parent.createSync(recursive: true);
  final outFile = File(outPath);
  if (outFile.existsSync()) outFile.deleteSync();

  final db = sqlite3.open(outPath);
  db.execute('''
    CREATE TABLE synsets (
      id TEXT PRIMARY KEY,
      pos TEXT NOT NULL,
      definition TEXT NOT NULL,
      members TEXT NOT NULL
    );
    CREATE TABLE senses (
      word TEXT NOT NULL,
      synset_id TEXT NOT NULL
    );
    CREATE INDEX idx_senses_word ON senses(word);
  ''');

  final synsetFiles = sourceDir
      .listSync()
      .whereType<File>()
      .where((f) {
        final name = f.uri.pathSegments.last;
        return RegExp(r'^(noun|verb|adj|adv)\..*\.json$').hasMatch(name);
      })
      .toList();

  print('Loading ${synsetFiles.length} synset category files...');
  final insertSynset = db.prepare(
    'INSERT OR REPLACE INTO synsets (id, pos, definition, members) VALUES (?, ?, ?, ?)',
  );
  db.execute('BEGIN');
  var synsetCount = 0;
  for (final file in synsetFiles) {
    final Map<String, dynamic> data = jsonDecode(file.readAsStringSync());
    for (final entry in data.entries) {
      final synsetId = entry.key;
      final Map<String, dynamic> synset = entry.value;
      final List<dynamic> defs = (synset['definition'] as List?) ?? const [];
      if (defs.isEmpty) continue;
      final pos = (synset['partOfSpeech'] as String?) ?? synsetId.split('-').last;
      final List<dynamic> members = (synset['members'] as List?) ?? const [];
      final memberWords = members.map((m) => (m as String).replaceAll('_', ' ')).join('|');
      insertSynset.execute([
        synsetId,
        pos,
        defs.join('; '),
        memberWords,
      ]);
      synsetCount++;
    }
  }
  db.execute('COMMIT');
  insertSynset.dispose();
  print('$synsetCount synsets loaded.');

  final entryFiles = sourceDir
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'^entries-.*\.json$').hasMatch(f.uri.pathSegments.last))
      .toList();

  print('Loading ${entryFiles.length} entry (word index) files...');
  final insertSense = db.prepare('INSERT INTO senses (word, synset_id) VALUES (?, ?)');
  db.execute('BEGIN');
  var senseCount = 0;
  for (final file in entryFiles) {
    final Map<String, dynamic> data = jsonDecode(file.readAsStringSync());
    for (final wordEntry in data.entries) {
      final word = wordEntry.key.replaceAll('_', ' ').toLowerCase();
      final Map<String, dynamic> byPos = wordEntry.value;
      for (final posEntry in byPos.entries) {
        final Map<String, dynamic> posData = posEntry.value;
        final List<dynamic> senses = (posData['sense'] as List?) ?? const [];
        for (final sense in senses) {
          final synsetId = sense['synset'] as String?;
          if (synsetId == null) continue;
          insertSense.execute([word, synsetId]);
          senseCount++;
        }
      }
    }
  }
  db.execute('COMMIT');
  insertSense.dispose();
  print('$senseCount word senses loaded.');

  db.execute('CREATE INDEX idx_synsets_pos ON synsets(pos);');
  db.execute('VACUUM;');
  db.dispose();
  print('Wrote $outPath (${(outFile.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB).');
}
