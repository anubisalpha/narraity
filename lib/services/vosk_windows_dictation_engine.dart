import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'dictation_engine.dart';
import 'vosk_ffi.dart';
import 'vosk_result_parser.dart';

/// Windows dictation via the vendored Vosk engine (see vosk_ffi.dart) fed by
/// raw microphone PCM from the `record` package. `vosk_flutter_service`'s
/// live-mic `SpeechService` only exists on its Android/iOS platform-channel
/// path — Windows always needed manual audio feeding into
/// `acceptWaveformBytes`, which is exactly what this class does directly
/// against our own FFI binding instead.
class VoskWindowsDictationEngine implements DictationEngine {
  VoskWindowsDictationEngine({required String modelPath}) : _modelPath = modelPath;

  static const _sampleRate = 16000;

  final String _modelPath;
  final _recorder = AudioRecorder();

  Pointer<Void>? _model;
  Pointer<Void>? _recognizer;
  StreamSubscription<Uint8List>? _audioSubscription;
  bool _isListening = false;

  @override
  bool get isListening => _isListening;

  @override
  Future<void> start(void Function(DictationResult result) onResult) async {
    if (_isListening) return;

    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission denied');
    }

    final vosk = VoskFfi.instance();
    _model ??= vosk.loadModel(_modelPath);
    _recognizer = vosk.createRecognizer(_model!, sampleRate: _sampleRate.toDouble());

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
      ),
    );

    _isListening = true;
    _audioSubscription = stream.listen((chunk) {
      final recognizer = _recognizer;
      if (recognizer == null) return;

      final endpointed = vosk.acceptWaveform(recognizer, chunk);
      if (endpointed) {
        final text = VoskResultParser.parseFinal(vosk.result(recognizer));
        if (text.isNotEmpty) {
          onResult(DictationResult(text: text, isFinal: true));
        }
      } else {
        final partial = VoskResultParser.parsePartial(vosk.partialResult(recognizer));
        if (partial.isNotEmpty) {
          onResult(DictationResult(text: partial, isFinal: false));
        }
      }
    });
  }

  @override
  Future<void> stop() async {
    if (!_isListening) return;
    _isListening = false;

    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _recorder.stop();

    final vosk = VoskFfi.instance();
    final recognizer = _recognizer;
    if (recognizer != null) {
      // Flush any trailing audio into a final result before releasing.
      vosk.finalResult(recognizer);
      vosk.freeRecognizer(recognizer);
      _recognizer = null;
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    final vosk = VoskFfi.instance();
    if (_model != null) {
      vosk.freeModel(_model!);
      _model = null;
    }
    await _recorder.dispose();
  }
}
