@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/project.dart';
import 'package:narraity/models/scene_snapshot.dart';
import 'package:narraity/services/library_service.dart';
import 'package:narraity/services/vault_service.dart';
import 'package:narraity/state/library_provider.dart';
import 'package:narraity/state/scene_history_provider.dart';
import 'package:narraity/state/vault_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opt-in per-project vault passwords: a project can use its own password,
/// distinct from the library-wide one, while unopted projects keep using the
/// library key exactly as before. These cover the risky part — the scene-
/// history re-signing migration and the key routing — at the provider layer
/// the (thin) UI drives.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory libraryRoot;
  late LibraryService library;
  late Project project;
  const sceneId = 'scene-1';
  const libraryPassword = 'library-wide password';
  const projectPassword = 'this-project-only password';

  ProviderContainer newContainer() {
    final container = ProviderContainer(
      overrides: [libraryServiceProvider.overrideWithValue(library)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<List<SnapshotVerification>> statuses(
    ProviderContainer container,
    Project proj,
  ) async {
    final history = await container.read(sceneHistoryServiceProvider(proj).future);
    return (await history.listWithStatus(sceneId)).map((v) => v.status).toList();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    libraryRoot = Directory.systemTemp.createTempSync('narraity_pp_vault_');
    library = LibraryService(rootOverride: libraryRoot);
    project = await library.createProject(title: 'The Long Winter', author: 'Test');
  });

  tearDown(() => libraryRoot.deleteSync(recursive: true));

  test('opting in re-signs library-key history onto the project key', () async {
    final container = newContainer();
    await container.read(vaultStatusProvider.notifier).setup(libraryPassword);

    final history = await container.read(sceneHistoryServiceProvider(project).future);
    await history.recordAutoSnapshot(sceneId, 'Snow came early.');
    expect(await statuses(container, project), [SnapshotVerification.valid]);

    // Opt this project into its own password.
    await container.read(vaultActionsProvider).setProjectPassword(project, projectPassword);

    expect(await container.read(projectHasOwnPasswordProvider(project).future), isTrue);
    // History still verifies — now under the project key, which is unlocked.
    expect(await statuses(container, project), [SnapshotVerification.valid]);
  });

  test('opting in signs previously-unsigned history (no library password)', () async {
    final container = newContainer();
    // No library password: history is written legacy-unsigned.
    final history = await container.read(sceneHistoryServiceProvider(project).future);
    await history.recordAutoSnapshot(sceneId, 'Unsigned beginnings.');
    expect(await statuses(container, project), [SnapshotVerification.legacyUnsigned]);

    await container.read(vaultActionsProvider).setProjectPassword(project, projectPassword);

    expect(await container.read(projectHasOwnPasswordProvider(project).future), isTrue);
    expect(await statuses(container, project), [SnapshotVerification.valid]);
  });

  test('after restart a per-project vault locks and unlocks independently', () async {
    final first = newContainer();
    final history = await first.read(sceneHistoryServiceProvider(project).future);
    await history.recordAutoSnapshot(sceneId, 'Chapter one.');
    await first.read(vaultActionsProvider).setProjectPassword(project, projectPassword);
    expect(await statuses(first, project), [SnapshotVerification.valid]);

    // "Restart" — keys live in memory only.
    final afterRestart = newContainer();
    expect(await afterRestart.read(projectHasOwnPasswordProvider(project).future), isTrue);
    // Signed, but the project password hasn't been entered → trusted-while-locked.
    expect(await statuses(afterRestart, project), [SnapshotVerification.locked]);

    final actions = afterRestart.read(vaultActionsProvider);
    expect(await actions.unlockProject(project, 'wrong'), isFalse);
    expect(await statuses(afterRestart, project), [SnapshotVerification.locked]);

    expect(await actions.unlockProject(project, projectPassword), isTrue);
    expect(await statuses(afterRestart, project), [SnapshotVerification.valid]);
  });

  test('a per-project backup opens with the project password, not the library one', () async {
    final container = newContainer();
    await container.read(vaultStatusProvider.notifier).setup(libraryPassword);
    await container.read(vaultActionsProvider).setProjectPassword(project, projectPassword);

    final generation = await container.read(vaultActionsProvider).refreshProject(project);
    expect(generation, isNotNull);

    final vault = container.read(vaultServiceProvider);
    // Opens with the project password.
    await vault.verifyVault(vaultFile: generation!, password: projectPassword);
    // The library password must NOT open it.
    await expectLater(
      vault.verifyVault(vaultFile: generation, password: libraryPassword),
      throwsA(isA<VaultOpenException>()),
    );
  });

  test('changing the library password leaves an opted-in project untouched', () async {
    // Two projects: one stays on the library key, one gets its own password.
    final other = await library.createProject(title: 'Sibling Book', author: 'Test');

    final container = newContainer();
    await container.read(vaultStatusProvider.notifier).setup(libraryPassword);

    final ownHistory = await container.read(sceneHistoryServiceProvider(project).future);
    await ownHistory.recordAutoSnapshot(sceneId, 'Owns its password.');
    final otherHistory = await container.read(sceneHistoryServiceProvider(other).future);
    await otherHistory.recordAutoSnapshot(sceneId, 'Stays on library key.');

    await container.read(vaultActionsProvider).setProjectPassword(project, projectPassword);

    // Change the LIBRARY password — must skip the opted-in project.
    const newLibraryPassword = 'rotated library password';
    await container.read(vaultActionsProvider).changePassword(
          oldPassword: libraryPassword,
          newPassword: newLibraryPassword,
        );

    // The opted-in project still verifies under its own (unchanged) password.
    expect(await statuses(container, project), [SnapshotVerification.valid]);
    // The library-key project verifies under the rotated library password.
    expect(await statuses(container, other), [SnapshotVerification.valid]);
  });

  test('changing a per-project password keeps history verifiable', () async {
    final container = newContainer();
    final history = await container.read(sceneHistoryServiceProvider(project).future);
    await history.recordAutoSnapshot(sceneId, 'Before change.');

    final actions = container.read(vaultActionsProvider);
    await actions.setProjectPassword(project, projectPassword);
    expect(await statuses(container, project), [SnapshotVerification.valid]);

    const newProjectPassword = 'rotated project password';
    await actions.changeProjectPassword(project, projectPassword, newProjectPassword);
    // Still valid under the new key.
    expect(await statuses(container, project), [SnapshotVerification.valid]);

    // After a restart the old password no longer unlocks; the new one does.
    final afterRestart = newContainer();
    final restartActions = afterRestart.read(vaultActionsProvider);
    expect(await restartActions.unlockProject(project, projectPassword), isFalse);
    expect(await restartActions.unlockProject(project, newProjectPassword), isTrue);
    expect(await statuses(afterRestart, project), [SnapshotVerification.valid]);
  });

  test('changing the password with a wrong current password is rejected', () async {
    final container = newContainer();
    final actions = container.read(vaultActionsProvider);
    await actions.setProjectPassword(project, projectPassword);

    await expectLater(
      actions.changeProjectPassword(project, 'wrong current', 'whatever new'),
      throwsA(isA<VaultOpenException>()),
    );
  });

  test('opting back out returns history to the library key', () async {
    final container = newContainer();
    await container.read(vaultStatusProvider.notifier).setup(libraryPassword);
    final history = await container.read(sceneHistoryServiceProvider(project).future);
    await history.recordAutoSnapshot(sceneId, 'Round trip.');

    final actions = container.read(vaultActionsProvider);
    await actions.setProjectPassword(project, projectPassword);
    expect(await container.read(projectHasOwnPasswordProvider(project).future), isTrue);

    await actions.removeProjectPassword(project);

    expect(await container.read(projectHasOwnPasswordProvider(project).future), isFalse);
    // Back on the library key, still valid (library is unlocked this session).
    expect(await statuses(container, project), [SnapshotVerification.valid]);
  });

  test('opting out is refused when there is no library password to return to', () async {
    final container = newContainer();
    // No library password set at all.
    await container.read(vaultActionsProvider).setProjectPassword(project, projectPassword);

    await expectLater(
      container.read(vaultActionsProvider).removeProjectPassword(project),
      throwsA(isA<VaultOpenException>()),
    );
  });
}
