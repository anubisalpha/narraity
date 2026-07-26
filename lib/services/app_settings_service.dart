import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'library_service.dart';

/// Consolidates the app's device-preference `SharedPreferences` keys into a
/// single syncable `_Settings/settings.json` file, so Drive sync can carry
/// them to a new device the same way it carries projects and vault
/// backups — closing the gap where a fresh install only restores
/// manuscripts, not how the app was set up.
///
/// Deliberately scoped to genuine app-wide *options* the user would want to
/// follow them to a new device: theme, dictation language/model-size
/// preference (not the downloaded model itself — that's a multi-hundred-MB
/// binary, re-downloaded per device same as before), spell check on/off,
/// Read Aloud voice/rate/pitch, vault retention/auto-refresh settings, and
/// the Drive auto-sync toggles themselves (immediate/daily/frequent).
/// Deliberately excludes Reference Panel visibility/width/pins — those are
/// already-documented machine workspace state (see
/// `reference_panel_provider.dart`), not "app options," and pins are
/// per-project besides.
class AppSettingsService {
  /// Pass [libraryService] to point at a specific library root (used by
  /// tests) instead of resolving the platform documents folder.
  AppSettingsService({LibraryService? libraryService})
      : _library = libraryService ?? LibraryService();

  final LibraryService _library;

  static const _keys = [
    'themeMode',
    'dictation.language',
    'dictation.modelSize',
    'spellCheck.enabled',
    'tts.rate',
    'tts.pitch',
    'tts.voiceName',
    'tts.voiceLocale',
    'editor.fontFamily',
    'editor.fontSize',
    'editor.lineHeight',
    'vault.retentionCount',
    'vault.autoRefresh',
    'driveSync.immediate',
    'driveSync.dailyEnabled',
    'driveSync.frequentIntervalMinutes',
  ];

  /// Reserved `_Settings/` folder at the library root — same "sits next to
  /// projects, deliberately outside any of them, `_`-prefixed so
  /// `LibraryService.listProjects` skips it" pattern as `_Vault/`.
  Future<Directory> settingsRoot() async {
    final root = await _library.libraryRoot();
    return Directory(p.join(root.path, '_Settings'));
  }

  File _settingsFile(Directory root) => File(p.join(root.path, 'settings.json'));

  /// Snapshots every known key currently in `SharedPreferences` to
  /// `_Settings/settings.json` — call before a Drive sync so local changes
  /// are picked up as a real file diff, same as any other sync target.
  Future<void> exportToFile() async {
    final prefs = await SharedPreferences.getInstance();
    final json = <String, Object?>{
      for (final key in _keys)
        if (prefs.containsKey(key)) key: prefs.get(key),
    };
    final root = await settingsRoot();
    await root.create(recursive: true);
    await _settingsFile(root).writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }

  /// Applies `_Settings/settings.json` back into `SharedPreferences` — call
  /// after a Drive sync in case it pulled a newer file from another device.
  /// A no-op if no file exists yet (first-ever sync on a fresh install with
  /// nothing to restore from Drive either).
  Future<void> importFromFile() async {
    final root = await settingsRoot();
    final file = _settingsFile(root);
    if (!await file.exists()) return;

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return; // corrupt/unreadable — leave current in-memory settings alone
    }

    final prefs = await SharedPreferences.getInstance();
    for (final key in _keys) {
      if (!json.containsKey(key)) continue;
      final value = json[key];
      switch (value) {
        case String s:
          await prefs.setString(key, s);
        case double d:
          await prefs.setDouble(key, d);
        case int i:
          await prefs.setInt(key, i);
        case bool b:
          await prefs.setBool(key, b);
      }
    }
  }
}
