import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Minimal hand-written Dart FFI binding to the real `libhunspell.dll`
/// (MPL/GPL/LGPL, hunspell/hunspell upstream) — only the handful of
/// functions this app actually needs.
///
/// No published Dart/Flutter package wraps Hunspell at all (checked
/// pub.dev directly), so — same rationale as `vosk_ffi.dart` for Vosk —
/// this binds to the native library by hand rather than depending on
/// something that doesn't exist. Unlike Vosk, there was no broken plugin to
/// route around; `libhunspell.dll` here is built from source
/// (`msvc/libhunspell.vcxproj`, `Release_dll|x64`, `PlatformToolset=v145`
/// to match this machine's installed Visual Studio toolset) and vendored at
/// `windows/hunspell/`, copied into the build output by
/// `windows/CMakeLists.txt` the same way `windows/vosk/` is.
///
/// Hunspell's C API (`hunspell.h`) is small and has been stable for years,
/// so this binding is low-maintenance.
class HunspellFfi {
  HunspellFfi._(DynamicLibrary lib)
      : _create = lib
            .lookup<
                NativeFunction<
                    Pointer<Void> Function(
                        Pointer<Utf8>, Pointer<Utf8>)>>('Hunspell_create')
            .asFunction(),
        _destroy = lib
            .lookup<NativeFunction<Void Function(Pointer<Void>)>>('Hunspell_destroy')
            .asFunction(),
        _spell = lib
            .lookup<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>)>>(
                'Hunspell_spell')
            .asFunction(),
        _suggest = lib
            .lookup<
                NativeFunction<
                    Int32 Function(
                        Pointer<Void>,
                        Pointer<Pointer<Pointer<Utf8>>>,
                        Pointer<Utf8>)>>('Hunspell_suggest')
            .asFunction(),
        _freeList = lib
            .lookup<
                NativeFunction<
                    Void Function(Pointer<Void>, Pointer<Pointer<Pointer<Utf8>>>,
                        Int32)>>('Hunspell_free_list')
            .asFunction(),
        _add = lib
            .lookup<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>)>>(
                'Hunspell_add')
            .asFunction(),
        _remove = lib
            .lookup<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>)>>(
                'Hunspell_remove')
            .asFunction();

  final Pointer<Void> Function(Pointer<Utf8> affpath, Pointer<Utf8> dpath) _create;
  final void Function(Pointer<Void> handle) _destroy;
  final int Function(Pointer<Void> handle, Pointer<Utf8> word) _spell;
  final int Function(
    Pointer<Void> handle,
    Pointer<Pointer<Pointer<Utf8>>> slst,
    Pointer<Utf8> word,
  ) _suggest;
  final void Function(
    Pointer<Void> handle,
    Pointer<Pointer<Pointer<Utf8>>> slst,
    int n,
  ) _freeList;
  final int Function(Pointer<Void> handle, Pointer<Utf8> word) _add;
  final int Function(Pointer<Void> handle, Pointer<Utf8> word) _remove;

  static HunspellFfi? _instance;

  /// Loads `libhunspell.dll` from beside the running executable (where
  /// `windows/CMakeLists.txt` copies it during build) or, in debug `flutter
  /// run`, from the vendored `windows/hunspell/` source directory as a
  /// fallback.
  static HunspellFfi instance() {
    if (_instance != null) return _instance!;
    if (!Platform.isWindows) {
      throw UnsupportedError('HunspellFfi is Windows-only for now; see PLAN.md Phase 4.5');
    }
    final lib = DynamicLibrary.open(_resolveLibraryPath());
    return _instance = HunspellFfi._(lib);
  }

  static String _resolveLibraryPath() {
    const fileName = 'libhunspell.dll';
    final besideExe = File('${File(Platform.resolvedExecutable).parent.path}\\$fileName');
    if (besideExe.existsSync()) return besideExe.path;

    // Debug fallback: running via `flutter run` from the project root.
    final vendored = File('windows\\hunspell\\$fileName');
    if (vendored.existsSync()) return vendored.path;

    throw StateError(
      'libhunspell.dll not found next to the executable or at windows/hunspell/. '
      'Was the CMake bundling step (windows/CMakeLists.txt) run?',
    );
  }

  /// Creates a dictionary handle from an `.aff`/`.dic` pair (real file
  /// paths, not asset paths — Hunspell reads them itself, not through
  /// Dart). Throws if the pair fails to load (bad paths, corrupt files).
  Pointer<Void> create(String affPath, String dicPath) {
    final affPtr = affPath.toNativeUtf8();
    final dicPtr = dicPath.toNativeUtf8();
    try {
      final handle = _create(affPtr, dicPtr);
      if (handle == nullptr) {
        throw StateError('Hunspell failed to load dictionary at $dicPath');
      }
      return handle;
    } finally {
      malloc.free(affPtr);
      malloc.free(dicPtr);
    }
  }

  void destroy(Pointer<Void> handle) => _destroy(handle);

  bool spell(Pointer<Void> handle, String word) {
    final wordPtr = word.toNativeUtf8();
    try {
      return _spell(handle, wordPtr) != 0;
    } finally {
      malloc.free(wordPtr);
    }
  }

  List<String> suggest(Pointer<Void> handle, String word) {
    final wordPtr = word.toNativeUtf8();
    final outSlst = malloc<Pointer<Pointer<Utf8>>>();
    try {
      final count = _suggest(handle, outSlst, wordPtr);
      if (count <= 0) return [];
      final slst = outSlst.value;
      final suggestions = [
        for (var i = 0; i < count; i++) slst[i].toDartString(),
      ];
      _freeList(handle, outSlst, count);
      return suggestions;
    } finally {
      malloc.free(wordPtr);
      malloc.free(outSlst);
    }
  }

  /// Adds [word] to the run-time (session) dictionary — not persisted to
  /// disk by Hunspell itself; the caller is responsible for remembering it
  /// across sessions if desired.
  bool addWord(Pointer<Void> handle, String word) {
    final wordPtr = word.toNativeUtf8();
    try {
      return _add(handle, wordPtr) == 0;
    } finally {
      malloc.free(wordPtr);
    }
  }

  bool removeWord(Pointer<Void> handle, String word) {
    final wordPtr = word.toNativeUtf8();
    try {
      return _remove(handle, wordPtr) == 0;
    } finally {
      malloc.free(wordPtr);
    }
  }
}
