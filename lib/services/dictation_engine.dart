/// One chunk of recognized speech.
class DictationResult {
  final String text;
  final bool isFinal;

  const DictationResult({required this.text, required this.isFinal});
}

/// Platform-specific speech-to-text engine. Windows uses a hand-written FFI
/// binding to Vosk (offline); Android uses the OS's native `SpeechRecognizer`
/// via the `speech_to_text` plugin — see PLAN.md Phase 1.3 and the 2026-07-24
/// decision notes in `vosk_ffi.dart` for why these differ per platform
/// despite the app otherwise being "one engine everywhere" where practical.
abstract class DictationEngine {
  /// True once [start] has succeeded and [stop] hasn't been called yet.
  bool get isListening;

  /// Starts listening, calling [onResult] for each partial and final
  /// recognition chunk. Throws if microphone permission is denied or the
  /// engine can't be initialized (e.g. missing model on Windows).
  Future<void> start(void Function(DictationResult result) onResult);

  Future<void> stop();

  Future<void> dispose();
}
