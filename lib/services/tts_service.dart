import 'package:flutter_tts/flutter_tts.dart';

/// One word-boundary event while speaking — a character range relative to
/// whatever text was most recently passed to [TtsService.speak], not the
/// full scene (the caller is responsible for offsetting if reading started
/// mid-document — see `scene_editor.dart`).
class TtsProgress {
  const TtsProgress({required this.start, required this.end});

  final int start;
  final int end;
}

/// A voice the installed TTS engine can use.
class TtsVoice {
  const TtsVoice({required this.name, required this.locale});

  final String name;
  final String locale;

  @override
  bool operator ==(Object other) =>
      other is TtsVoice && other.name == name && other.locale == locale;

  @override
  int get hashCode => Object.hash(name, locale);
}

/// Parses `FlutterTts.getVoices`' raw platform-channel response (a
/// `List<dynamic>` of `Map`s with at least `name`/`locale` keys — exact key
/// casing and extra fields vary by platform). Pure, no plugin dependency,
/// fully unit-testable — same "keep parsing separate from the platform
/// wrapper" precedent as `VoskResultParser`.
List<TtsVoice> parseTtsVoices(dynamic raw) {
  if (raw is! List) return [];
  final voices = <TtsVoice>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final name = entry['name']?.toString() ?? '';
    if (name.isEmpty) continue;
    voices.add(TtsVoice(name: name, locale: entry['locale']?.toString() ?? ''));
  }
  return voices;
}

/// Thin wrapper around `flutter_tts` — offline on both v1 platforms (Windows
/// SAPI/UWP voices, Android `TextToSpeech`), no model download needed unlike
/// dictation's Vosk models, since both OSes already ship a TTS engine.
/// Unlike the Vosk Flutter plugin this project replaced with a hand-written
/// FFI binding (see README "Why not a Vosk plugin?"), `flutter_tts` ships a
/// real native Windows implementation, so no such workaround is needed here.
class TtsService {
  final FlutterTts _tts = FlutterTts();

  TtsService() {
    _tts.setProgressHandler(
      (text, start, end, word) => _onProgress?.call(TtsProgress(start: start, end: end)),
    );
    _tts.setCompletionHandler(() => _onComplete?.call());
    _tts.setCancelHandler(() => _onComplete?.call());
    _tts.setErrorHandler((message) => _onComplete?.call());
  }

  void Function(TtsProgress progress)? _onProgress;
  void Function()? _onComplete;

  Future<List<TtsVoice>> availableVoices() async => parseTtsVoices(await _tts.getVoices);

  Future<void> setVoice(TtsVoice voice) =>
      _tts.setVoice({'name': voice.name, 'locale': voice.locale});

  Future<void> setSpeechRate(double rate) => _tts.setSpeechRate(rate);

  Future<void> setPitch(double pitch) => _tts.setPitch(pitch);

  /// Speaks [text], calling [onProgress] for each word boundary and
  /// [onComplete] when speech finishes, is stopped, or errors — the caller
  /// doesn't need to distinguish those, since in every case reading has
  /// stopped and the UI should return to its idle state.
  Future<void> speak(
    String text, {
    required void Function(TtsProgress progress) onProgress,
    required void Function() onComplete,
  }) async {
    _onProgress = onProgress;
    _onComplete = onComplete;
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();

  Future<void> dispose() async {
    _onProgress = null;
    _onComplete = null;
    await _tts.stop();
  }
}
