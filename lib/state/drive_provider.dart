import 'dart:async';
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

/// Thrown internally when [DriveConnectionNotifier.cancelConnect] backs out
/// of an in-progress sign-in — never surfaced to callers as an error message.
class _ConnectCancelled implements Exception {}

/// Whether the app is currently connected to Google Drive. Signing in is
/// always an explicit user action (the "Connect" button in Settings) — never
/// triggered implicitly by a provider, since it pops the system browser.
class DriveConnectionNotifier extends Notifier<DriveConnectionStatus> {
  /// Non-null only while a [connect] call is in flight — lets
  /// [cancelConnect] back out of it. Real bug fixed here: with no way to
  /// cancel, a sign-in that never completes (browser tab closed without
  /// finishing, consent denied silently, network dropped) left the UI
  /// showing a permanent spinner with no way out.
  Completer<Never>? _cancelSignal;

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
  /// Returns an error message on failure, or null on success (including a
  /// user-initiated cancel, which isn't an error).
  Future<String?> connect() async {
    state = DriveConnectionStatus.signingIn;
    final auth = ref.read(driveAuthServiceProvider);
    final cancelSignal = Completer<Never>();
    _cancelSignal = cancelSignal;

    final signInFuture = auth.ensureSignedIn();
    // There's no way to truly abort clientViaUserConsent's local
    // server/browser flow — if the user cancels, this keeps running in the
    // background and either eventually succeeds (fine: the *next* connect()
    // call will just find it already signed in) or fails. Either way,
    // nothing here is still listening for it once cancelled, so swallow the
    // result here to avoid an "unhandled exception" purely from losing the
    // race below.
    unawaited(signInFuture.then((_) {}, onError: (_) {}));

    try {
      await Future.any<Object?>([signInFuture, cancelSignal.future]);
      if (!identical(_cancelSignal, cancelSignal)) return null; // superseded by a later call
      state = DriveConnectionStatus.signedIn;
      return null;
    } catch (error) {
      if (!identical(_cancelSignal, cancelSignal)) return null;
      state = DriveConnectionStatus.signedOut;
      return error is _ConnectCancelled ? null : error.toString();
    } finally {
      if (identical(_cancelSignal, cancelSignal)) _cancelSignal = null;
    }
  }

  /// Backs out of an in-progress [connect] call — the "Cancel" button shown
  /// alongside the signing-in spinner.
  void cancelConnect() {
    _cancelSignal?.completeError(_ConnectCancelled());
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
