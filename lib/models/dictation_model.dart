/// The two dictation languages this app offers by default (PLAN.md: "en-GB
/// as the default", en-US as the alternative). Nothing is bundled with the
/// app — both download on first use to keep the install size small on both
/// Windows and Android (Phase 1.3 scope decision, 2026-07-24).
enum DictationLanguage { enUs, enGb }

extension DictationLanguageCode on DictationLanguage {
  /// Vosk catalog language code (`lang` field in model-list.json).
  String get catalogCode => switch (this) {
        DictationLanguage.enUs => 'en-us',
        DictationLanguage.enGb => 'en-gb',
      };

  String get displayName => switch (this) {
        DictationLanguage.enUs => 'English (US)',
        DictationLanguage.enGb => 'English (UK)',
      };
}

/// Accuracy/size tier. [large] doesn't mean "the biggest model that exists"
/// — for en-US the catalog's true "big" model is ~1.8GB, far past what's
/// reasonable for an auto-download; [large] instead means "the smallest
/// non-small model available", which lands on very different real sizes per
/// language (en-GB ~281MB, en-US ~124MB "lgraph"). See
/// DictationModelService.resolveModel — verified against the live catalog
/// 2026-07-24, not hardcoded to a specific model name.
enum DictationModelSize { small, large }

extension DictationModelSizeLabel on DictationModelSize {
  String get label => switch (this) {
        DictationModelSize.small => 'Small — faster download, good for everyday dictation',
        DictationModelSize.large => 'Large — bigger download, better accuracy',
      };
}

/// One resolved, downloadable model — resolved from Vosk's *live* catalog
/// rather than a hardcoded name/version. Model names get superseded over
/// time (verified 2026-07-24: the catalog listed several obsolete `en-us`
/// entries), so pinning a specific version risks quietly breaking when it's
/// eventually pulled. See DictationModelService.resolveModel.
class ResolvedDictationModel {
  final DictationLanguage language;
  final DictationModelSize size;
  final String modelName;
  final String downloadUrl;
  final String sizeText;

  const ResolvedDictationModel({
    required this.language,
    required this.size,
    required this.modelName,
    required this.downloadUrl,
    required this.sizeText,
  });
}

enum DictationDownloadStatus { notDownloaded, downloading, ready, failed }

/// A model already sitting on disk in `.models/` — used by the Settings
/// screen so users can see and delete downloaded models directly, rather
/// than only ever downloading more (switching language/size leaves the
/// previous model's files behind).
class DownloadedDictationModel {
  final String modelName;
  final int sizeBytes;

  const DownloadedDictationModel({required this.modelName, required this.sizeBytes});

  String get sizeText {
    final mb = sizeBytes / (1024 * 1024);
    return mb >= 1024 ? '${(mb / 1024).toStringAsFixed(1)}GB' : '${mb.toStringAsFixed(0)}MB';
  }
}
