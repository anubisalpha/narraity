import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Extracts the bundled Open English WordNet SQLite database from the
/// Flutter asset bundle to a real file — `sqlite3` opens files by path, not
/// in-memory asset buffers. Same "copy once, reuse the extracted file"
/// pattern as [SpellCheckDictionaryService] for the Hunspell dictionaries.
class WordnetDictionaryService {
  /// Pass [rootOverride] to point extraction at a specific directory (used
  /// by tests) instead of resolving the platform support folder.
  WordnetDictionaryService({Directory? rootOverride}) : _root = rootOverride;

  Directory? _root;

  Future<Directory> _wordnetRoot() async {
    if (_root != null) return _root!;
    final support = await getApplicationSupportDirectory();
    return _root = Directory(p.join(support.path, 'wordnet'));
  }

  /// Ensures `wordnet.sqlite` exists on disk under the wordnet root,
  /// copying from `assets/wordnet/wordnet.sqlite` the first time. Returns
  /// its real file path.
  Future<String> ensureExtracted() async {
    final root = await _wordnetRoot();
    await root.create(recursive: true);

    final dbFile = File(p.join(root.path, 'wordnet.sqlite'));
    if (!await dbFile.exists()) {
      final data = await rootBundle.load('assets/wordnet/wordnet.sqlite');
      await dbFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    }
    return dbFile.path;
  }
}
