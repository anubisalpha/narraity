import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/drive_sync_log_service.dart';
import 'package:narraity/services/drive_sync_planner.dart';
import 'package:narraity/services/library_service.dart';
import 'package:narraity/state/drive_auto_sync_provider.dart';
import 'package:narraity/state/drive_provider.dart';
import 'package:narraity/state/library_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_drive_remote_store.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// Skips `DriveConnectionNotifier`'s real `_restore()` (a `path_provider`
/// platform-channel call with no mock registered in a plain provider test)
/// by just reporting signed-in immediately — this test only needs
/// `runFullSyncAcrossAllTargets`'s signed-in gate to pass, not a real sign-in.
class _FixedSignedInNotifier extends DriveConnectionNotifier {
  @override
  DriveConnectionStatus build() => DriveConnectionStatus.signedIn;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('immediate sync defaults to off', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _settle();

    expect(container.read(driveImmediateSyncEnabledProvider), isFalse);
  });

  test('daily sync defaults to off', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _settle();

    expect(container.read(driveDailySyncEnabledProvider), isFalse);
  });

  test('frequent sync interval defaults to 0 (off)', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _settle();

    expect(container.read(driveFrequentSyncIntervalProvider), 0);
  });

  test('toggling immediate sync persists across a fresh provider instance', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(driveImmediateSyncEnabledProvider.notifier).set(true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(driveImmediateSyncPrefKey), isTrue);
  });

  test('setting the frequent interval persists the chosen minutes', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(driveFrequentSyncIntervalProvider.notifier).set(15);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(driveFrequentSyncIntervalPrefKey), 15);
  });

  test('setting daily sync persists the chosen value', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(driveDailySyncEnabledProvider.notifier).set(true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(driveDailySyncPrefKey), isTrue);
  });

  group('runFullSyncAcrossAllTargets', () {
    late Directory libraryRoot;
    late FakeDriveRemoteStore remote;
    late ProviderContainer container;

    setUp(() {
      libraryRoot = Directory.systemTemp.createTempSync('narraity_full_sync_test_');
      remote = FakeDriveRemoteStore();
      container = ProviderContainer(
        overrides: [
          libraryServiceProvider.overrideWithValue(LibraryService(rootOverride: libraryRoot)),
          driveConnectionProvider.overrideWith(_FixedSignedInNotifier.new),
          driveRemoteStoreProvider.overrideWith((ref) async => remote),
          driveSyncLogServiceProvider.overrideWithValue(
            DriveSyncLogService(rootOverride: libraryRoot),
          ),
        ],
      );
      addTearDown(container.dispose);
    });

    tearDown(() {
      libraryRoot.deleteSync(recursive: true);
    });

    // Every reserved-folder target found missing from sync in the same
    // audit that added Series (2026-08-09): Global Ideas, App-Wide Goals,
    // Review Sessions, and Archived/Deleted projects. One assertion per
    // target instead of one test each — they're all the same "is this
    // combined target actually in the list and does its content really
    // come down" shape, just a different reserved folder name.
    for (final folderName in [
      '_Series',
      '_GlobalIdeas',
      '_GlobalGoals',
      '_ReviewSessions',
      '_Archived',
      '_Deleted',
    ]) {
      test('pulls down $folderName content', () async {
        remote.seed(folderName, 'record.json', utf8.encode('{"hello":"world"}'));

        // manualSyncAllProvider, not runFullSyncAcrossAllTargets directly —
        // that function needs a real `Ref`, which a bare `ProviderContainer`
        // doesn't satisfy; this provider already captures one internally
        // (see its own definition) and is the same path the "Sync All Now"
        // button in Settings actually calls.
        await container.read(manualSyncAllProvider)();

        final file = File(p.join(libraryRoot.path, folderName, 'record.json'));
        expect(await file.exists(), isTrue, reason: '$folderName was not synced');
        expect(await file.readAsString(), '{"hello":"world"}');
      });
    }

    test('a clean run leaves the last-sync-error clear', () async {
      remote.seed('_Series', 'record.json', utf8.encode('{"ok":true}'));
      await container.read(manualSyncAllProvider)();
      expect(container.read(driveLastSyncErrorProvider), isNull);
    });
  });

  test('a failing sync records the first failure in the last-sync-error '
      'provider, then a clean run clears it', () async {
    final root = Directory.systemTemp.createTempSync('narraity_sync_err_');
    addTearDown(() => root.deleteSync(recursive: true));

    final throwing = _ThrowingDriveRemoteStore();
    final container = ProviderContainer(
      overrides: [
        libraryServiceProvider.overrideWithValue(LibraryService(rootOverride: root)),
        driveConnectionProvider.overrideWith(_FixedSignedInNotifier.new),
        driveRemoteStoreProvider.overrideWith((ref) async => throwing),
        driveSyncLogServiceProvider.overrideWithValue(
          DriveSyncLogService(rootOverride: root),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(manualSyncAllProvider)();
    final error = container.read(driveLastSyncErrorProvider);
    expect(error, isNotNull);
    expect(error, contains('boom'));

    // Once the remote stops throwing, the next clean run heals the state.
    throwing.failing = false;
    await container.read(manualSyncAllProvider)();
    expect(container.read(driveLastSyncErrorProvider), isNull);
  });
}

/// A [FakeDriveRemoteStore] whose enumeration step throws while [failing] is
/// true — `sync()` calls `listFiles` first, so this fails every target and
/// exercises the last-sync-error path.
class _ThrowingDriveRemoteStore extends FakeDriveRemoteStore {
  bool failing = true;

  @override
  Future<Map<String, DriveRemoteFile>> listFiles(String projectFolderName) {
    if (failing) throw StateError('boom');
    return super.listFiles(projectFolderName);
  }
}
