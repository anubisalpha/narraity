import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'dictation_engine.dart';

/// Android dictation via the OS's native on-device `SpeechRecognizer`
/// (`speech_to_text` plugin). Android imposes a short silence timeout that
/// this plugin can't remove — see PLAN.md Phase 1.3 research notes — so this
/// class auto-restarts listening every time the platform stops it, as long
/// as dictation mode is still toggled on, to approximate the continuous
/// "talk and it types" experience Windows gets natively from Vosk's
/// streaming API.
class AndroidDictationEngine implements DictationEngine {
  final _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _shouldKeepListening = false;
  void Function(DictationResult result)? _onResult;

  @override
  bool get isListening => _isListening;

  @override
  Future<void> start(void Function(DictationResult result) onResult) async {
    if (_isListening) return;
    _onResult = onResult;
    _shouldKeepListening = true;

    final available = await _speech.initialize(
      onStatus: _handleStatus,
    );
    if (!available) {
      throw StateError('Speech recognition is not available on this device');
    }

    _isListening = true;
    await _listenOnce();
  }

  Future<void> _listenOnce() async {
    await _speech.listen(
      onResult: (result) {
        final callback = _onResult;
        if (callback == null) return;
        callback(DictationResult(
          text: result.recognizedWords,
          isFinal: result.finalResult,
        ));
      },
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        onDevice: true,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  void _handleStatus(String status) {
    // Android's recognizer stops itself after a pause; restart transparently
    // while the user still has dictation toggled on.
    if (status == stt.SpeechToText.notListeningStatus &&
        _shouldKeepListening &&
        _isListening) {
      _listenOnce();
    }
  }

  @override
  Future<void> stop() async {
    _shouldKeepListening = false;
    _isListening = false;
    await _speech.stop();
  }

  @override
  Future<void> dispose() async {
    await stop();
    _onResult = null;
  }
}
