import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Catches Flutter framework errors, async/platform errors, and anything
/// escaping `runZonedGuarded`, appending them to a plain-text log file so a
/// crash or silent failure can be diagnosed after the fact instead of only
/// being visible in a console that's since scrolled away or closed.
///
/// Log lives at `Documents/Narraity/.logs/app.log` — inside the same
/// local-first library folder as everything else the app writes, so it's
/// easy to find and safe to attach when reporting a bug.
class AppLogger {
  AppLogger._();

  static File? _logFile;
  static const _maxBytesBeforeRotate = 2 * 1024 * 1024; // 2 MB

  static Future<void> _ensureFile() async {
    if (_logFile != null) return;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'Narraity', '.logs'));
    await dir.create(recursive: true);
    _logFile = File(p.join(dir.path, 'app.log'));
  }

  static Future<void> logError(
    Object error,
    StackTrace? stack, {
    String context = 'uncaught',
  }) async {
    try {
      await _ensureFile();
      final file = _logFile!;
      if (await file.exists() && await file.length() > _maxBytesBeforeRotate) {
        await file.rename('${file.path}.1');
        _logFile = File(file.path);
      }
      final entry = StringBuffer()
        ..writeln('---')
        ..writeln('${DateTime.now().toIso8601String()} [$context]')
        ..writeln(error.toString());
      if (stack != null) {
        entry.writeln(stack.toString());
      }
      await _logFile!.writeAsString(entry.toString(), mode: FileMode.append);
    } catch (_) {
      // Logging must never itself crash the app.
    }
    // Still surface in the debug console during development.
    debugPrint('[$context] $error');
  }

  /// Wires up all three error surfaces:
  /// - `FlutterError.onError` — widget build/layout/paint errors
  /// - `PlatformDispatcher.onError` — async errors outside any Flutter zone
  /// - the `runZonedGuarded` handler passed to [run] — anything else
  static Future<void> run(FutureOr<void> Function() body) async {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details); // keep default red-screen in debug
      logError(details.exception, details.stack, context: 'flutter');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      logError(error, stack, context: 'platform');
      return true; // handled
    };

    await runZonedGuarded(
      body,
      (error, stack) => logError(error, stack, context: 'zone'),
    );
  }

  /// Path to the current log file, once initialized — useful for a future
  /// "Open log folder" / "Copy log" support-menu action.
  static String? get currentLogPath => _logFile?.path;
}
