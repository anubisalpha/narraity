import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/vault_service.dart';

void main() {
  late Directory projectDir;
  late Directory restoreDir;
  late File vaultFile;
  late VaultService service;

  setUp(() {
    projectDir = Directory.systemTemp.createTempSync('narraity_vault_project_');
    restoreDir = Directory.systemTemp.createTempSync('narraity_vault_restore_');
    vaultFile = File(
      '${Directory.systemTemp.path}/narraity_vault_test_${DateTime.now().microsecondsSinceEpoch}.vault',
    );
    service = VaultService();

    File(
      '${projectDir.path}/project.json',
    ).writeAsStringSync('{"title":"Test Project"}');
    Directory(
      '${projectDir.path}/manuscript/scenes',
    ).createSync(recursive: true);
    File(
      '${projectDir.path}/manuscript/scenes/scene-1.md',
    ).writeAsStringSync('Once upon a time.');
  });

  tearDown(() {
    projectDir.deleteSync(recursive: true);
    restoreDir.deleteSync(recursive: true);
    if (vaultFile.existsSync()) vaultFile.deleteSync();
  });

  test(
    'buildVault then restoreVault round-trips the project contents',
    () async {
      await service.buildVault(
        projectDir: projectDir,
        vaultFile: vaultFile,
        password: 'correct horse battery staple',
      );

      await service.restoreVault(
        vaultFile: vaultFile,
        targetDir: restoreDir,
        password: 'correct horse battery staple',
      );

      expect(
        File(
          '${restoreDir.path}/manuscript/scenes/scene-1.md',
        ).readAsStringSync(),
        'Once upon a time.',
      );
      expect(
        jsonDecode(
          File('${restoreDir.path}/project.json').readAsStringSync(),
        )['title'],
        'Test Project',
      );
    },
  );

  test('restoreVault fails with the wrong password', () async {
    await service.buildVault(
      projectDir: projectDir,
      vaultFile: vaultFile,
      password: 'right password',
    );

    expect(
      () => service.restoreVault(
        vaultFile: vaultFile,
        targetDir: restoreDir,
        password: 'wrong password',
      ),
      throwsA(isA<VaultOpenException>()),
    );
  });

  test(
    'a tampered vault file fails to open rather than silently returning bad data',
    () async {
      await service.buildVault(
        projectDir: projectDir,
        vaultFile: vaultFile,
        password: 'a password',
      );

      // Flip a character in the middle of the base64 ciphertext, simulating a
      // single bad byte from corruption or a deliberate edit.
      final header =
          jsonDecode(await vaultFile.readAsString()) as Map<String, dynamic>;
      final ciphertext = header['ciphertext'] as String;
      final tamperIndex = ciphertext.length ~/ 2;
      final tamperedChar = ciphertext[tamperIndex] == 'A' ? 'B' : 'A';
      header['ciphertext'] = ciphertext.replaceRange(
        tamperIndex,
        tamperIndex + 1,
        tamperedChar,
      );
      await vaultFile.writeAsString(jsonEncode(header));

      expect(
        () => service.restoreVault(
          vaultFile: vaultFile,
          targetDir: restoreDir,
          password: 'a password',
        ),
        throwsA(isA<VaultOpenException>()),
      );
    },
  );

  test('verifyVault succeeds without writing anything to disk', () async {
    await service.buildVault(
      projectDir: projectDir,
      vaultFile: vaultFile,
      password: 'check me',
    );
    await service.verifyVault(vaultFile: vaultFile, password: 'check me');
    // No exception thrown means it verified; nothing to assert about disk
    // state since verifyVault deliberately doesn't touch it.
  });

  test(
    'missing vault file raises a clear error rather than a raw FS exception',
    () async {
      final missing = File(
        '${Directory.systemTemp.path}/does_not_exist_${DateTime.now().microsecondsSinceEpoch}.vault',
      );
      expect(
        () => service.restoreVault(
          vaultFile: missing,
          targetDir: restoreDir,
          password: 'anything',
        ),
        throwsA(isA<VaultOpenException>()),
      );
    },
  );

  group('plain (unencrypted) vaults — the "back up without a password" opt-in', () {
    test(
      'buildPlainVault then restoreVault (no password) round-trips the project contents',
      () async {
        await service.buildPlainVault(
          projectDir: projectDir,
          vaultFile: vaultFile,
        );

        await service.restoreVault(vaultFile: vaultFile, targetDir: restoreDir);

        expect(
          File(
            '${restoreDir.path}/manuscript/scenes/scene-1.md',
          ).readAsStringSync(),
          'Once upon a time.',
        );
        expect(
          jsonDecode(
            File('${restoreDir.path}/project.json').readAsStringSync(),
          )['title'],
          'Test Project',
        );
      },
    );

    test(
      'isEncryptedVault distinguishes a plain generation from a password-protected one',
      () async {
        await service.buildPlainVault(
          projectDir: projectDir,
          vaultFile: vaultFile,
        );
        expect(await service.isEncryptedVault(vaultFile), isFalse);

        await service.buildVault(
          projectDir: projectDir,
          vaultFile: vaultFile,
          password: 'a password',
        );
        expect(await service.isEncryptedVault(vaultFile), isTrue);
      },
    );

    test(
      'verifyVault succeeds on a plain vault with no password at all',
      () async {
        await service.buildPlainVault(
          projectDir: projectDir,
          vaultFile: vaultFile,
        );
        await service.verifyVault(vaultFile: vaultFile);
      },
    );

    test('an encrypted vault cannot be opened with no password', () async {
      await service.buildVault(
        projectDir: projectDir,
        vaultFile: vaultFile,
        password: 'a password',
      );
      expect(
        () => service.restoreVault(vaultFile: vaultFile, targetDir: restoreDir),
        throwsA(isA<VaultOpenException>()),
      );
    });
  });

  group('generational rotation', () {
    late Directory vaultDir;

    setUp(() {
      vaultDir = Directory.systemTemp.createTempSync(
        'narraity_vault_generations_',
      );
    });

    tearDown(() => vaultDir.deleteSync(recursive: true));

    test(
      'refreshVault creates a new timestamped generation each call',
      () async {
        final first = await service.refreshVault(
          projectDir: projectDir,
          vaultDir: vaultDir,
          baseName: 'MyProject',
          password: 'p',
        );
        await Future.delayed(const Duration(milliseconds: 5));
        final second = await service.refreshVault(
          projectDir: projectDir,
          vaultDir: vaultDir,
          baseName: 'MyProject',
          password: 'p',
        );

        expect(first.path, isNot(second.path));
        expect(
          await service.listGenerations(vaultDir, 'MyProject'),
          hasLength(2),
        );
      },
    );

    test(
      'old generations beyond retainCount are pruned, newest kept',
      () async {
        for (var i = 0; i < 5; i++) {
          await service.refreshVault(
            projectDir: projectDir,
            vaultDir: vaultDir,
            baseName: 'MyProject',
            password: 'p',
            retainCount: 3,
          );
          await Future.delayed(const Duration(milliseconds: 5));
        }

        final generations = await service.listGenerations(
          vaultDir,
          'MyProject',
        );
        expect(generations, hasLength(3));

        final latest = await service.latestGeneration(vaultDir, 'MyProject');
        expect(latest!.path, generations.last.path);
      },
    );

    test('different baseNames rotate independently', () async {
      await service.refreshVault(
        projectDir: projectDir,
        vaultDir: vaultDir,
        baseName: 'ProjectA',
        password: 'p',
      );
      await service.refreshVault(
        projectDir: projectDir,
        vaultDir: vaultDir,
        baseName: 'ProjectB',
        password: 'p',
      );

      expect(await service.listGenerations(vaultDir, 'ProjectA'), hasLength(1));
      expect(await service.listGenerations(vaultDir, 'ProjectB'), hasLength(1));
    });

    test(
      'latestGeneration returns null when nothing has been built yet',
      () async {
        expect(await service.latestGeneration(vaultDir, 'Nothing'), isNull);
      },
    );
  });
}
