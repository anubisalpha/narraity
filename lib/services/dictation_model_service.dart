import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/dictation_model.dart';
import 'app_logger.dart';
import 'library_service.dart';

/// Downloads and extracts Vosk speech models. Own implementation rather than
/// reusing `vosk_flutter_service`'s `ModelLoader` — see vosk_ffi.dart for why
/// that package isn't a dependency at all. This is a small, self-contained
/// piece of logic (HTTP GET + zip extract), not worth pulling in a plugin for.
///
/// Models are shared across all projects (not per-project data), so they
/// live in a `.models/` folder at the library root, next to `_GlobalIdeas/`.
class DictationModelService {
  DictationModelService(this._library);

  final LibraryService _library;

  static const _catalogUrl = 'https://alphacephei.com/vosk/models/model-list.json';

  /// Last-known-good models to fall back to if the live catalog is
  /// unreachable or its shape changes unexpectedly — verified working
  /// 2026-07-24. Prefer [resolveModel]'s live lookup whenever possible;
  /// catalog entries get marked obsolete/replaced over time.
  static const _fallback = {
    (DictationLanguage.enUs, DictationModelSize.small): (
      name: 'vosk-model-small-en-us-0.15',
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip',
      sizeText: '~40MB',
    ),
    (DictationLanguage.enUs, DictationModelSize.large): (
      name: 'vosk-model-en-us-0.22-lgraph',
      url: 'https://alphacephei.com/vosk/models/vosk-model-en-us-0.22-lgraph.zip',
      sizeText: '~124MB',
    ),
    (DictationLanguage.enGb, DictationModelSize.small): (
      name: 'vosk-model-small-en-gb-0.15',
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-en-gb-0.15.zip',
      sizeText: '~40MB',
    ),
    (DictationLanguage.enGb, DictationModelSize.large): (
      name: 'vosk-model-en-gb-0.1',
      url: 'https://alphacephei.com/vosk/models/vosk-model-en-gb-0.1.zip',
      sizeText: '~281MB',
    ),
  };

  Future<Directory> _modelsDir() async {
    final root = await _library.libraryRoot();
    final dir = Directory(p.join(root.path, '.models'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Looks up the current active model for [language]/[size] from Vosk's
  /// live catalog. Falls back to a pinned last-known-good model (logged via
  /// [AppLogger]) if the catalog can't be fetched or parsed.
  ///
  /// [DictationModelSize.large] picks the *smallest non-small* active model
  /// for the language, rather than a hardcoded name — this naturally lands
  /// on very different real models per language (en-GB's only "big" option
  /// is ~281MB; en-US's true "big" is ~1.8GB, so this picks its ~124MB
  /// "lgraph" variant instead). See DictationModelSize's doc comment.
  Future<ResolvedDictationModel> resolveModel(
    DictationLanguage language,
    DictationModelSize size,
  ) async {
    try {
      final response = await http.get(Uri.parse(_catalogUrl)).timeout(
            const Duration(seconds: 10),
          );
      final entries = (jsonDecode(response.body) as List<dynamic>)
          .cast<Map<String, dynamic>>();

      final candidates = entries
          .where((e) => e['lang'] == language.catalogCode && e['obsolete'] == 'false')
          .toList();

      final Map<String, dynamic>? chosen;
      if (size == DictationModelSize.small) {
        final small = candidates.where((e) => e['type'] == 'small');
        chosen = small.isNotEmpty ? small.first : null;
      } else {
        final nonSmall = candidates.where((e) => e['type'] != 'small').toList()
          ..sort((a, b) => (a['size'] as int).compareTo(b['size'] as int));
        chosen = nonSmall.isNotEmpty ? nonSmall.first : null;
      }

      if (chosen == null) {
        throw StateError(
          'No active $size model found for ${language.catalogCode}',
        );
      }

      return ResolvedDictationModel(
        language: language,
        size: size,
        modelName: chosen['name'] as String,
        downloadUrl: chosen['url'] as String,
        sizeText: chosen['size_text'] as String,
      );
    } catch (error, stack) {
      AppLogger.logError(
        error,
        stack,
        context: 'dictation-catalog-fallback (${language.catalogCode}, $size)',
      );
      final fallback = _fallback[(language, size)]!;
      return ResolvedDictationModel(
        language: language,
        size: size,
        modelName: fallback.name,
        downloadUrl: fallback.url,
        sizeText: fallback.sizeText,
      );
    }
  }

  Future<bool> isDownloaded(ResolvedDictationModel model) async {
    final dir = Directory(p.join((await _modelsDir()).path, model.modelName));
    return dir.exists();
  }

  Future<String> modelPath(ResolvedDictationModel model) async {
    return p.join((await _modelsDir()).path, model.modelName);
  }

  /// Lists every model folder currently on disk, with its size — for the
  /// Settings screen's "manage downloaded models" section.
  Future<List<DownloadedDictationModel>> listDownloadedModels() async {
    final dir = await _modelsDir();
    final models = <DownloadedDictationModel>[];
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      var bytes = 0;
      await for (final file in entity.list(recursive: true)) {
        if (file is File) bytes += await file.length();
      }
      models.add(DownloadedDictationModel(
        modelName: p.basename(entity.path),
        sizeBytes: bytes,
      ));
    }
    models.sort((a, b) => a.modelName.compareTo(b.modelName));
    return models;
  }

  /// Deletes a downloaded model folder by name, freeing its disk space.
  Future<void> deleteModelByName(String modelName) async {
    final dir = Directory(p.join((await _modelsDir()).path, modelName));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Downloads and extracts [model], reporting 0.0–1.0 progress. Returns the
  /// extracted model's folder path (what Vosk's `vosk_model_new` expects).
  Stream<double> download(ResolvedDictationModel model) async* {
    final modelsDir = await _modelsDir();
    final destination = Directory(p.join(modelsDir.path, model.modelName));
    if (await destination.exists()) return;

    final request = http.Request('GET', Uri.parse(model.downloadUrl));
    final response = await http.Client().send(request);
    final total = response.contentLength ?? 0;

    final bytes = <int>[];
    var received = 0;
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      received += chunk.length;
      if (total > 0) yield received / total;
    }

    final archive = ZipDecoder().decodeBytes(bytes);
    extractArchiveToDisk(archive, modelsDir.path);
    yield 1.0;
  }
}
