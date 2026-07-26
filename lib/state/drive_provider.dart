import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:path/path.dart' as p;

import '../config/drive_oauth_config.dart';
import '../models/project.dart';
import '../services/drive_auth_service.dart';
import '../services/drive_remote_store.dart';
import '../services/drive_sync_service.dart';
import '../services/library_service.dart';

final driveAuthServiceProvider = Provider<DriveAuthService>((ref) {
  final secret = DriveOAuthConfig.clientSecret.isEmpty ? null : DriveOAuthConfig.clientSecret;
  return DriveAuthService(clientId: ClientId(DriveOAuthConfig.clientId, secret));
});

enum DriveConnectionStatus { unknown, signedOut, signingIn, signedIn }

/// Whether the app is currently connected to Google Drive. Signing in is
/// always an explicit user action (the "Connect" button in Settings) — never
/// triggered implicitly by a provider, since it pops the system browser.
class DriveConnectionNotifier extends Notifier<DriveConnectionStatus> {
  @override
  DriveConnectionStatus build() {
    _restore();
    return DriveConnectionStatus.unknown;
  }

  Future<void> _restore() async {
    final auth = ref.read(driveAuthServiceProvider);
    state = await auth.isSignedIn ? DriveConnectionStatus.signedIn : DriveConnectionStatus.signedOut;
  }

  /// Attempts to connect, silently reusing a saved token if there is one.
  /// Returns an error message on failure, or null on success.
  Future<String?> connect() async {
    state = DriveConnectionStatus.signingIn;
    final auth = ref.read(driveAuthServiceProvider);
    try {
      await auth.ensureSignedIn();
      state = DriveConnectionStatus.signedIn;
      return null;
    } catch (error) {
      state = DriveConnectionStatus.signedOut;
      return error.toString();
    }
  }

  Future<void> disconnect() async {
    final auth = ref.read(driveAuthServiceProvider);
    await auth.signOut();
    state = DriveConnectionStatus.signedOut;
  }
}

final driveConnectionProvider =
    NotifierProvider<DriveConnectionNotifier, DriveConnectionStatus>(DriveConnectionNotifier.new);

/// The sync engine, valid only while signed in — callers should gate use of
/// this on `driveConnectionProvider == DriveConnectionStatus.signedIn`.
final driveSyncServiceProvider = FutureProvider<DriveSyncService>((ref) async {
  final status = ref.watch(driveConnectionProvider);
  if (status != DriveConnectionStatus.signedIn) {
    throw StateError('Not signed in to Google Drive.');
  }
  final auth = ref.read(driveAuthServiceProvider);
  // Already signed in, so this just returns the cached client — no browser
  // popup, no network round trip.
  final client = await auth.ensureSignedIn();
  return DriveSyncService(remoteStore: GoogleDriveRemoteStore(client));
});

/// The on-disk project folder [project] lives in — what [DriveSyncService]
/// needs but [Project] itself doesn't carry (it only has the folder *name*).
/// Takes [LibraryService] directly rather than a `Ref`, since `Ref` and
/// `WidgetRef` aren't compatible types and this is called from both plain
/// providers and `ConsumerState`.
Future<Directory> projectDirectory(LibraryService library, Project project) async {
  final root = await library.libraryRoot();
  return Directory(p.join(root.path, project.folderName));
}
