import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Extracts a bundled Hunspell `.aff`/`.dic` pair from the Flutter asset
/// bundle to a real file Hunspell can open directly (its C API takes file
/// paths, not in-memory buffers — Flutter assets live inside the app
/// package/APK, which Hunspell's own file I/O can't read). Mirrors
/// `DictationModelService`'s "make sure the real file exists on disk before
/// handing a path to the native engine" shape, minus the network download —
/// the dictionary ships with the app, so this only ever copies once.
class SpellCheckDictionaryService {
  /// Pass [rootOverride] to point extraction at a specific directory (used
  /// by tests) instead of resolving the platform support folder.
  SpellCheckDictionaryService({Directory? rootOverride}) : _root = rootOverride;

  Directory? _root;

  Future<Directory> _dictionariesRoot() async {
    if (_root != null) return _root!;
    final support = await getApplicationSupportDirectory();
    return _root = Directory(p.join(support.path, 'dictionaries'));
  }

  /// Ensures `<languageTag>.aff`/`.dic` exist on disk under the
  /// dictionaries root, copying from `assets/dictionaries/<languageTag>/`
  /// the first time. Returns their real file paths.
  Future<(String affPath, String dicPath)> ensureExtracted(String languageTag) async {
    final root = await _dictionariesRoot();
    final dir = Directory(p.join(root.path, languageTag));
    await dir.create(recursive: true);

    final affFile = File(p.join(dir.path, '$languageTag.aff'));
    final dicFile = File(p.join(dir.path, '$languageTag.dic'));

    if (!await affFile.exists()) {
      await _copyAsset('assets/dictionaries/$languageTag/$languageTag.aff', affFile);
    }
    if (!await dicFile.exists()) {
      await _copyAsset('assets/dictionaries/$languageTag/$languageTag.dic', dicFile);
    }

    return (affFile.path, dicFile.path);
  }

  Future<void> _copyAsset(String assetPath, File destination) async {
    final data = await rootBundle.load(assetPath);
    await destination.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }
}
