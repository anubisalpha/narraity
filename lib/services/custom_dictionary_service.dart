import 'dart:io';

import 'package:path/path.dart' as p;

import 'library_service.dart';

/// Persists words added via "Add to Dictionary" (spelling panel) so they
/// survive an app restart — previously `Hunspell_add` only touched the
/// in-memory run-time dictionary (see `hunspell_ffi.dart`), so nothing
/// carried over between sessions at all. Stored as one plain-text file per
/// language at the library root (`_Settings/custom-words-<languageTag>.txt`,
/// one word per line) — same reserved-folder convention as `_GlobalIdeas/`,
/// app-wide rather than per-project since the dictionary itself is app-wide.
class CustomDictionaryService {
  /// Pass [libraryService] to point at a specific library root (used by
  /// tests) instead of resolving the platform documents folder.
  CustomDictionaryService({LibraryService? libraryService})
      : _library = libraryService ?? LibraryService();

  final LibraryService _library;

  Future<File> _fileFor(String languageTag) async {
    final root = await _library.libraryRoot();
    final dir = Directory(p.join(root.path, '_Settings'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, 'custom-words-$languageTag.txt'));
  }

  /// Every custom word persisted for [languageTag], in the order they were
  /// added — replayed through `Hunspell_add` when a `SpellCheckService`
  /// loads.
  Future<List<String>> loadWords(String languageTag) async {
    final file = await _fileFor(languageTag);
    if (!await file.exists()) return [];
    final lines = await file.readAsLines();
    return lines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  }

  /// Appends [word] if it isn't already stored — a no-op for a duplicate
  /// (added twice in the same session, or already restored from a previous
  /// one) rather than growing the file with repeats.
  Future<void> addWord(String languageTag, String word) async {
    final trimmed = word.trim();
    if (trimmed.isEmpty) return;

    final existing = await loadWords(languageTag);
    if (existing.contains(trimmed)) return;

    final file = await _fileFor(languageTag);
    await file.writeAsString('$trimmed\n', mode: FileMode.append);
  }

  /// Removes [word] from the persisted list — a no-op if it was never
  /// there. Rewrites the whole file rather than a targeted line delete;
  /// this list is realistically tens of words, not worth a more careful
  /// in-place edit.
  Future<void> removeWord(String languageTag, String word) async {
    final existing = await loadWords(languageTag);
    if (!existing.remove(word.trim())) return;

    final file = await _fileFor(languageTag);
    await file.writeAsString(existing.map((w) => '$w\n').join());
  }
}
