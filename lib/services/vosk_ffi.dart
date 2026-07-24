import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Minimal hand-written Dart FFI binding to the real `libvosk.dll` (Apache
/// 2.0, AlphaCephei) — only the ~7 functions this app actually needs.
///
/// We bind directly instead of depending on `vosk_flutter_service` because
/// that package's Windows CMake integration is broken in its only published
/// release (0.1.2): the DLLs it downloads land one folder deeper than its
/// own `windows/CMakeLists.txt` expects, and that same CMakeLists.txt also
/// runs a stale `flutter pub run vosk_flutter install` command (leftover
/// from a package rename — the package is now `vosk_flutter_service`) with
/// `COMMAND_ERROR_IS_FATAL ANY`, which aborts the Windows build outright.
/// Depending on that package at all — even unused — registers its
/// CMakeLists.txt into the build via Flutter's plugin system, so the only
/// fix short of waiting on an unmaintained single-contributor package is to
/// not depend on it. The DLLs themselves are vendored at `windows/vosk/`
/// (verified working, downloaded from the same upstream release) and copied
/// into the build output by `windows/CMakeLists.txt`.
///
/// Vosk's C API is small and has been stable for years, so this binding is
/// low-maintenance — see `windows/vosk/vosk_api.h` for the authoritative
/// signatures this was written against.
class VoskFfi {
  VoskFfi._(DynamicLibrary lib)
      : _modelNew = lib
            .lookup<NativeFunction<Pointer<Void> Function(Pointer<Utf8>)>>(
                'vosk_model_new')
            .asFunction(),
        _modelFree = lib
            .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
                'vosk_model_free')
            .asFunction(),
        _recognizerNew = lib
            .lookup<
                NativeFunction<
                    Pointer<Void> Function(
                        Pointer<Void>, Float)>>('vosk_recognizer_new')
            .asFunction(),
        _recognizerFree = lib
            .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
                'vosk_recognizer_free')
            .asFunction(),
        _recognizerReset = lib
            .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
                'vosk_recognizer_reset')
            .asFunction(),
        _acceptWaveform = lib
            .lookup<
                NativeFunction<
                    Int32 Function(Pointer<Void>, Pointer<Uint8>,
                        Int32)>>('vosk_recognizer_accept_waveform')
            .asFunction(),
        _result = lib
            .lookup<
                NativeFunction<
                    Pointer<Utf8> Function(
                        Pointer<Void>)>>('vosk_recognizer_result')
            .asFunction(),
        _partialResult = lib
            .lookup<
                NativeFunction<
                    Pointer<Utf8> Function(
                        Pointer<Void>)>>('vosk_recognizer_partial_result')
            .asFunction(),
        _finalResult = lib
            .lookup<
                NativeFunction<
                    Pointer<Utf8> Function(
                        Pointer<Void>)>>('vosk_recognizer_final_result')
            .asFunction();

  final Pointer<Void> Function(Pointer<Utf8> modelPath) _modelNew;
  final void Function(Pointer<Void> model) _modelFree;
  final Pointer<Void> Function(Pointer<Void> model, double sampleRate)
      _recognizerNew;
  final void Function(Pointer<Void> recognizer) _recognizerFree;
  final void Function(Pointer<Void> recognizer) _recognizerReset;
  final int Function(Pointer<Void> recognizer, Pointer<Uint8> data, int length)
      _acceptWaveform;
  final Pointer<Utf8> Function(Pointer<Void> recognizer) _result;
  final Pointer<Utf8> Function(Pointer<Void> recognizer) _partialResult;
  final Pointer<Utf8> Function(Pointer<Void> recognizer) _finalResult;

  static VoskFfi? _instance;

  /// Loads `libvosk.dll` from beside the running executable (where
  /// `windows/CMakeLists.txt` copies it during build) or, in debug `flutter
  /// run`, from the vendored `windows/vosk/` source directory as a fallback.
  static VoskFfi instance() {
    if (_instance != null) return _instance!;
    if (!Platform.isWindows) {
      throw UnsupportedError('VoskFfi is Windows-only; see PLAN.md Phase 1.3');
    }
    final lib = DynamicLibrary.open(_resolveLibraryPath());
    return _instance = VoskFfi._(lib);
  }

  static String _resolveLibraryPath() {
    const fileName = 'libvosk.dll';
    final besideExe = File('${File(Platform.resolvedExecutable).parent.path}\\$fileName');
    if (besideExe.existsSync()) return besideExe.path;

    // Debug fallback: running via `flutter run` from the project root.
    final vendored = File('windows\\vosk\\$fileName');
    if (vendored.existsSync()) return vendored.path;

    throw StateError(
      'libvosk.dll not found next to the executable or at windows/vosk/. '
      'Was the CMake bundling step (windows/CMakeLists.txt) run?',
    );
  }

  Pointer<Void> loadModel(String modelPath) {
    final pathPtr = modelPath.toNativeUtf8();
    try {
      final model = _modelNew(pathPtr);
      if (model == nullptr) {
        throw StateError('Vosk failed to load model at $modelPath');
      }
      return model;
    } finally {
      malloc.free(pathPtr);
    }
  }

  void freeModel(Pointer<Void> model) => _modelFree(model);

  Pointer<Void> createRecognizer(Pointer<Void> model, {double sampleRate = 16000}) {
    final recognizer = _recognizerNew(model, sampleRate);
    if (recognizer == nullptr) {
      throw StateError('Vosk failed to create a recognizer');
    }
    return recognizer;
  }

  void freeRecognizer(Pointer<Void> recognizer) => _recognizerFree(recognizer);

  void resetRecognizer(Pointer<Void> recognizer) => _recognizerReset(recognizer);

  /// Feeds a chunk of 16-bit mono PCM audio. Returns true when Vosk has
  /// detected an endpoint (a full [result] is ready), matching the upstream
  /// C API's return convention.
  bool acceptWaveform(Pointer<Void> recognizer, List<int> pcm16Bytes) {
    final buffer = malloc<Uint8>(pcm16Bytes.length);
    try {
      buffer.asTypedList(pcm16Bytes.length).setAll(0, pcm16Bytes);
      return _acceptWaveform(recognizer, buffer, pcm16Bytes.length) == 1;
    } finally {
      malloc.free(buffer);
    }
  }

  String result(Pointer<Void> recognizer) => _result(recognizer).toDartString();

  String partialResult(Pointer<Void> recognizer) =>
      _partialResult(recognizer).toDartString();

  String finalResult(Pointer<Void> recognizer) =>
      _finalResult(recognizer).toDartString();
}
