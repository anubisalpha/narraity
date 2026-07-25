import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/history_signing_key_manager.dart';

void main() {
  late Directory tempDir;
  late HistorySigningKeyManager manager;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_keymgr_test_');
    manager = HistorySigningKeyManager(
      saltFile: File('${tempDir.path}/_Vault/salt'),
      verifierFile: File('${tempDir.path}/_Vault/verifier'),
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('a fresh library is neither configured nor unlocked', () async {
    expect(await manager.isConfigured, isFalse);
    expect(manager.isUnlocked, isFalse);
    expect(manager.currentKey, isNull);
  });

  test('setup configures the library and leaves it unlocked', () async {
    await manager.setup('correct horse battery');

    expect(await manager.isConfigured, isTrue);
    expect(manager.isUnlocked, isTrue);
    expect(manager.currentKey, isNotNull);
  });

  test('unlock before setup fails rather than adopting the typed password', () async {
    expect(await manager.unlock('anything at all'), isFalse);
    expect(await manager.isConfigured, isFalse);
    expect(manager.isUnlocked, isFalse);
  });

  test('the correct password unlocks and reproduces the same key', () async {
    await manager.setup('correct horse battery');
    final original = manager.currentKey;
    manager.lock();

    expect(await manager.unlock('correct horse battery'), isTrue);
    expect(manager.currentKey, original);
  });

  test('a wrong password is rejected and leaves the manager locked', () async {
    await manager.setup('correct horse battery');
    manager.lock();

    expect(await manager.unlock('wrong horse battery'), isFalse);
    expect(manager.isUnlocked, isFalse);
    expect(manager.currentKey, isNull);
  });

  test('a wrong password does not disturb an already unlocked key', () async {
    await manager.setup('correct horse battery');
    final original = manager.currentKey;

    expect(await manager.unlock('wrong horse battery'), isFalse);
    expect(manager.currentKey, original, reason: 'a failed unlock must not clobber the key');
  });

  test('deriveKeyFor is stable per password and does not change state', () async {
    await manager.setup('correct horse battery');
    manager.lock();

    final first = await manager.deriveKeyFor('correct horse battery');
    final second = await manager.deriveKeyFor('correct horse battery');
    final other = await manager.deriveKeyFor('a different password');

    expect(first, second);
    expect(first, isNot(other));
    expect(manager.isUnlocked, isFalse, reason: 'deriveKeyFor must not unlock');
  });

  test('rekey switches which password is accepted', () async {
    await manager.setup('first password');
    final oldKey = manager.currentKey;

    await manager.rekey('second password');
    expect(manager.currentKey, isNot(oldKey));

    manager.lock();
    expect(await manager.unlock('first password'), isFalse);
    expect(await manager.unlock('second password'), isTrue);
  });

  test('rekey keeps the salt, so the same password derives the same key', () async {
    await manager.setup('first password');
    final saltBefore = await File('${tempDir.path}/_Vault/salt').readAsString();
    final keyForSecond = await manager.deriveKeyFor('second password');

    await manager.rekey('second password');

    expect(await File('${tempDir.path}/_Vault/salt').readAsString(), saltBefore);
    expect(manager.currentKey, keyForSecond);
  });
}
