import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/release_notes_service.dart';

final releaseNotesServiceProvider = Provider<ReleaseNotesService>((ref) => ReleaseNotesService());

/// One fetch-or-fall-back-to-cache per app session — same session-caching
/// rationale as `updateCheckProvider`.
final releaseNotesProvider =
    FutureProvider<(List<ReleaseNote>, DateTime?, bool)>((ref) {
  return ref.read(releaseNotesServiceProvider).load();
});

/// Deliberately a plain `SharedPreferences` key, not one of
/// `AppSettingsService`'s Drive-synced keys — "have I seen the What's New
/// dialog for this version" is per-device state (a fresh device should see
/// it too), not a preference that should follow the user to a new install.
const _lastSeenVersionKey = 'releaseNotes.lastSeenVersion';

Future<String?> readLastSeenVersion() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_lastSeenVersionKey);
}

Future<void> writeLastSeenVersion(String version) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_lastSeenVersionKey, version);
}

/// Resolves to the just-installed release's notes the first time the app
/// launches after an update (running version differs from the last one the
/// user was shown a What's New dialog for, and that version's notes are
/// actually in the fetched/cached list) — `null` otherwise, meaning
/// `WhatsNewDialog` shouldn't show at all this launch.
final whatsNewProvider = FutureProvider<ReleaseNote?>((ref) async {
  final info = await PackageInfo.fromPlatform();
  final lastSeen = await readLastSeenVersion();
  if (lastSeen == info.version) return null;

  final (releases, _, _) = await ref.watch(releaseNotesProvider.future);
  for (final release in releases) {
    if (release.version == info.version) return release;
  }
  return null;
});
