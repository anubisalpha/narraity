import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dictation_model.dart';
import '../services/android_dictation_engine.dart';
import '../services/dictation_engine.dart';
import '../services/dictation_model_service.dart';
import '../services/vosk_windows_dictation_engine.dart';
import 'library_provider.dart';

final dictationModelServiceProvider = Provider<DictationModelService>(
  (ref) => DictationModelService(ref.watch(libraryServiceProvider)),
);

const _languagePrefKey = 'dictation.language';

/// User's chosen dictation language (PLAN.md default: en-GB), persisted.
class DictationLanguageNotifier extends Notifier<DictationLanguage> {
  @override
  DictationLanguage build() {
    _restore();
    return DictationLanguage.enGb;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_languagePrefKey);
    if (saved == null) return;
    state = DictationLanguage.values.firstWhere(
      (l) => l.name == saved,
      orElse: () => DictationLanguage.enGb,
    );
  }

  Future<void> select(DictationLanguage language) async {
    state = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languagePrefKey, language.name);
  }
}

final dictationLanguageProvider =
    NotifierProvider<DictationLanguageNotifier, DictationLanguage>(
  DictationLanguageNotifier.new,
);

const _sizePrefKey = 'dictation.modelSize';

/// User's chosen accuracy/size tier, persisted. Defaults to small — the
/// large tier is an opt-in tradeoff (bigger download), not the default.
class DictationModelSizeNotifier extends Notifier<DictationModelSize> {
  @override
  DictationModelSize build() {
    _restore();
    return DictationModelSize.small;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_sizePrefKey);
    if (saved == null) return;
    state = DictationModelSize.values.firstWhere(
      (s) => s.name == saved,
      orElse: () => DictationModelSize.small,
    );
  }

  Future<void> select(DictationModelSize size) async {
    state = size;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sizePrefKey, size.name);
  }
}

final dictationModelSizeProvider =
    NotifierProvider<DictationModelSizeNotifier, DictationModelSize>(
  DictationModelSizeNotifier.new,
);

/// Resolves the current language + size against Vosk's live model catalog.
final resolvedDictationModelProvider =
    FutureProvider<ResolvedDictationModel>((ref) async {
  final language = ref.watch(dictationLanguageProvider);
  final size = ref.watch(dictationModelSizeProvider);
  final service = ref.watch(dictationModelServiceProvider);
  return service.resolveModel(language, size);
});

final dictationModelDownloadedProvider = FutureProvider<bool>((ref) async {
  final model = await ref.watch(resolvedDictationModelProvider.future);
  final service = ref.watch(dictationModelServiceProvider);
  return service.isDownloaded(model);
});

/// All models currently on disk — for the Settings screen. Invalidate after
/// downloading or deleting a model to refresh.
final downloadedDictationModelsProvider =
    FutureProvider<List<DownloadedDictationModel>>((ref) async {
  final service = ref.watch(dictationModelServiceProvider);
  return service.listDownloadedModels();
});

/// The active engine instance, created lazily once a model is ready. Null on
/// Android until first use isn't required (no model download needed there).
final dictationEngineProvider = FutureProvider<DictationEngine>((ref) async {
  if (Platform.isAndroid) {
    return AndroidDictationEngine();
  }

  final model = await ref.watch(resolvedDictationModelProvider.future);
  final service = ref.watch(dictationModelServiceProvider);
  final path = await service.modelPath(model);
  return VoskWindowsDictationEngine(modelPath: path);
});

/// Whether dictation is currently active in the editor.
final isDictatingProvider = StateProvider<bool>((ref) => false);

/// Ranges of text inserted by dictation that haven't been reviewed yet —
/// simple `(start, end)` character offsets into the scene's current content,
/// used to render a "review dictated text" affordance. See scene_editor.dart;
/// this is a lighter-weight stand-in for full inline highlighting until the
/// editor moves to a rich-text widget (PLAN.md Phase 2.5+ territory).
final unreviewedDictationRangesProvider =
    StateProvider<List<(int start, int end)>>((ref) => []);
