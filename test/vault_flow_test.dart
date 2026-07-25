import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/profile_entry.dart';
import 'package:narraity/models/project.dart';
import 'package:narraity/models/scene_snapshot.dart';
import 'package:narraity/services/library_service.dart';
import 'package:narraity/services/profile_service.dart';
import 'package:narraity/services/story_notes_service.dart';
import 'package:narraity/services/vault_service.dart';
import 'package:narraity/state/library_provider.dart';
import 'package:narraity/state/reference_provider.dart';
import 'package:narraity/state/scene_history_provider.dart';
import 'package:narraity/state/vault_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end walkthrough of the vault flows exactly as the UI drives them —
/// set up a password, sign history, back up, "restart" the app, unlock, restore
/// into a sibling folder, change the password. The screens are thin wrappers
/// over these provider calls, so this covers the behaviour that matters without
/// depending on a running desktop window.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory libraryRoot;
  late LibraryService library;
  late Project project;
  const sceneId = 'scene-1';
  const firstPassword = 'first vault password';
  const secondPassword = 'second vault password';

  /// A fresh container over the same library folder — how the app looks after
  /// a restart, since the derived key lives only in memory.
  ProviderContainer newContainer() {
    final container = ProviderContainer(
      overrides: [libraryServiceProvider.overrideWithValue(library)],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    libraryRoot = Directory.systemTemp.createTempSync('narraity_vault_flow_');
    library = LibraryService(rootOverride: libraryRoot);
    project = await library.createProject(title: 'The Long Winter', author: 'Test');
  });

  tearDown(() => libraryRoot.deleteSync(recursive: true));

  test('full vault lifecycle: setup, sign, back up, restart, unlock, restore', () async {
    final container = newContainer();

    // 1. A library with no vault password reports notConfigured.
    expect(await container.read(vaultStatusProvider.future), VaultStatus.notConfigured);

    // 2. Setting the password leaves the vault unlocked.
    await container.read(vaultStatusProvider.notifier).setup(firstPassword);
    expect(container.read(vaultStatusProvider).value, VaultStatus.unlocked);

    // 3. Writing a scene now produces *signed* history — this is what wiring
    //    the key manager into sceneHistoryServiceProvider buys.
    final history = await container.read(sceneHistoryServiceProvider(project).future);
    await history.recordAutoSnapshot(sceneId, 'Snow came early that year.');
    expect(
      (await history.listWithStatus(sceneId)).map((v) => v.status),
      [SnapshotVerification.valid],
    );

    // 4. "Back up now" writes a generation under the reserved _Vault folder,
    //    outside every project directory.
    final generation = await container.read(vaultActionsProvider).refreshProject(project);
    expect(generation, isNotNull);
    expect(await generation!.exists(), isTrue);
    expect(
      p.relative(generation.path, from: libraryRoot.path).replaceAll('\\', '/'),
      startsWith('_Vault/${project.folderName}/'),
    );

    // The vault folder must not read back as a project.
    expect((await library.listProjects()).map((pr) => pr.folderName), [project.folderName]);

    // 5. Restart: the password is not persisted, so the vault is locked again,
    //    but it is *configured* — not back to square one.
    final afterRestart = newContainer();
    expect(await afterRestart.read(vaultStatusProvider.future), VaultStatus.locked);

    // Existing signed history is trusted rather than flagged while locked.
    final lockedHistory = await afterRestart.read(sceneHistoryServiceProvider(project).future);
    expect(
      (await lockedHistory.listWithStatus(sceneId)).map((v) => v.status),
      [SnapshotVerification.locked],
    );

    // 6. A wrong password is rejected; the right one unlocks.
    expect(await afterRestart.read(vaultStatusProvider.notifier).unlock('not it'), isFalse);
    expect(afterRestart.read(vaultStatusProvider).value, VaultStatus.locked);
    expect(
      await afterRestart.read(vaultStatusProvider.notifier).unlock(firstPassword),
      isTrue,
    );

    // 7. After unlocking, history verifies for real — no false tamper flags.
    final unlockedHistory = await afterRestart.read(sceneHistoryServiceProvider(project).future);
    expect(
      (await unlockedHistory.listWithStatus(sceneId)).map((v) => v.status),
      [SnapshotVerification.valid],
    );

    // 8. Restore into a sibling folder leaves the original untouched and the
    //    copy complete.
    final restoredDir = Directory(p.join(libraryRoot.path, '${project.folderName} (restored)'));
    await afterRestart.read(vaultServiceProvider).restoreVault(
          vaultFile: generation,
          targetDir: restoredDir,
          password: firstPassword,
        );

    expect(await File(p.join(restoredDir.path, 'project.json')).exists(), isTrue);
    final restoredLibrary = LibraryService(rootOverride: libraryRoot);
    expect((await restoredLibrary.listProjects()).length, 2);

    final restoredHistoryDir =
        Directory(p.join(restoredDir.path, 'manuscript', 'scenes', '$sceneId.history'));
    expect(await restoredHistoryDir.exists(), isTrue,
        reason: 'the vault must carry version history, not just the prose');
  });

  test('a vault backup carries characters, world entries and notes', () async {
    final container = newContainer();
    await container.read(vaultStatusProvider.notifier).setup(firstPassword);

    // Reference material lives inside the project folder, so it should be
    // swept up by the vault automatically — this pins that down rather than
    // assuming it.
    final characters = await container.read(characterServiceProvider(project).future);
    final created = await characters.create(name: 'Elena Vance');
    final world = await container.read(worldServiceProvider(project).future);
    await world.create(name: 'Ashfall Keep', category: 'Location');
    final notes = await container.read(storyNotesServiceProvider(project).future);
    await notes.createFolder('Research');
    await notes.createNote(title: 'Filed note', folder: 'Research');

    final generation = await container.read(vaultActionsProvider).refreshProject(project);
    final restoredDir = Directory(p.join(libraryRoot.path, 'restored-with-references'));
    await container.read(vaultServiceProvider).restoreVault(
          vaultFile: generation!,
          targetDir: restoredDir,
          password: firstPassword,
        );

    final restoredCharacters = ProfileService(restoredDir, ProfileKind.character);
    final restoredWorld = ProfileService(restoredDir, ProfileKind.world);
    final restoredNotes = StoryNotesService(restoredDir);

    expect((await restoredCharacters.list()).map((e) => e.name), ['Elena Vance']);
    expect((await restoredCharacters.list()).single.id, created.id);
    expect((await restoredWorld.list()).single.category, 'Location');
    expect(await restoredNotes.folders(), ['Research']);
    expect((await restoredNotes.listAll()).single.folder, 'Research');
  });

  test('a wrong password cannot open a vault generation', () async {
    final container = newContainer();
    await container.read(vaultStatusProvider.notifier).setup(firstPassword);
    final generation = await container.read(vaultActionsProvider).refreshProject(project);

    await expectLater(
      container.read(vaultServiceProvider).verifyVault(
            vaultFile: generation!,
            password: 'the wrong password',
          ),
      throwsA(isA<VaultOpenException>()),
    );
  });

  test('changing the password re-signs history and keeps it verifiable', () async {
    final container = newContainer();
    await container.read(vaultStatusProvider.notifier).setup(firstPassword);

    final history = await container.read(sceneHistoryServiceProvider(project).future);
    await history.recordAutoSnapshot(sceneId, 'Chapter one.');
    await history.recordCheckpoint(sceneId, 'Chapter one, revised.', 'First pass');

    final statuses = <String>[];
    await container.read(vaultActionsProvider).changePassword(
          oldPassword: firstPassword,
          newPassword: secondPassword,
          onProgress: statuses.add,
        );

    expect(container.read(vaultStatusProvider).value, VaultStatus.unlocked);
    expect(statuses, isNotEmpty, reason: 'the dialog needs progress to display');

    // A fresh generation is written under the new password.
    final generations = await container.read(vaultGenerationsProvider(project).future);
    expect(generations, isNotEmpty);
    await container.read(vaultServiceProvider).verifyVault(
          vaultFile: generations.first,
          password: secondPassword,
        );

    // Restart: only the new password works, and history verifies under it
    // rather than looking tampered.
    final afterRestart = newContainer();
    expect(await afterRestart.read(vaultStatusProvider.future), VaultStatus.locked);
    expect(await afterRestart.read(vaultStatusProvider.notifier).unlock(firstPassword), isFalse);
    expect(await afterRestart.read(vaultStatusProvider.notifier).unlock(secondPassword), isTrue);

    final rekeyedHistory = await afterRestart.read(sceneHistoryServiceProvider(project).future);
    final verified = await rekeyedHistory.listWithStatus(sceneId);
    expect(verified.map((v) => v.status), everyElement(SnapshotVerification.valid));
    expect(await rekeyedHistory.reconstructContent(sceneId), 'Chapter one, revised.');

    // And writing continues to chain correctly after the change.
    await rekeyedHistory.recordAutoSnapshot(sceneId, 'Chapter one, revised. Chapter two.');
    expect(
      (await rekeyedHistory.listWithStatus(sceneId)).map((v) => v.status),
      everyElement(SnapshotVerification.valid),
    );
  });

  test('a locked vault skips backup instead of failing', () async {
    final container = newContainer();
    await container.read(vaultStatusProvider.notifier).setup(firstPassword);
    await container.read(vaultStatusProvider.notifier).lock();

    expect(await container.read(vaultActionsProvider).refreshProject(project), isNull);
  });

  test('retention count limits how many generations are kept', () async {
    final container = newContainer();
    await container.read(vaultRetentionCountProvider.notifier).set(3);
    await container.read(vaultStatusProvider.notifier).setup(firstPassword);

    final actions = container.read(vaultActionsProvider);
    for (var i = 0; i < 5; i++) {
      await actions.refreshProject(project);
    }

    final generations = await container.read(vaultGenerationsProvider(project).future);
    expect(generations, hasLength(3));
    // Newest first, so the list is in descending filename order.
    final names = generations.map((f) => p.basename(f.path)).toList();
    final sortedDescending = [...names]..sort((a, b) => b.compareTo(a));
    expect(names, sortedDescending);
  });
}
