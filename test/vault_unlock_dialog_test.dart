import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/project.dart';
import 'package:narraity/state/vault_provider.dart';
import 'package:narraity/widgets/vault_unlock_dialog.dart';

/// Widget-level coverage of the vault *unlock* gate — the dialog a user meets
/// when opening a project whose vault is configured but locked.
///
/// This deliberately fakes [VaultStatusNotifier] rather than driving a real
/// Argon2id derivation: the crypto correctness (right password unlocks, wrong
/// one doesn't) is already covered at the provider level by `vault_flow_test`,
/// and real Argon2id can't run inside `testWidgets`' fake-async zone anyway.
/// What's under test here is the *dialog's own wiring* — that it calls unlock,
/// shows the error on a false result, pops `true` on success, pops `false` on
/// skip, and renders the right per-project vs library copy.
const _correctPassword = 'correct horse battery';

class _FakeVaultStatusNotifier extends VaultStatusNotifier {
  @override
  Future<VaultStatus> build() async => VaultStatus.locked;

  @override
  Future<bool> unlock(String password) async => password == _correctPassword;
}

void main() {
  /// The dialog's `TextField` has `autofocus: true`, whose blinking-cursor
  /// timer never lets `pumpAndSettle` settle — pump a bounded number of fixed
  /// steps instead. Fast here since the faked unlock is synchronous.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<List<bool?>> pumpDialog(WidgetTester tester, {Project? forProject}) async {
    final results = <bool?>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultStatusProvider.overrideWith(_FakeVaultStatusNotifier.new),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async => results.add(
                  await showVaultUnlockDialog(context, project: forProject),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    return results;
  }

  testWidgets('wrong password shows an error and keeps the dialog open',
      (tester) async {
    final results = await pumpDialog(tester);
    expect(find.text('Unlock vault'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'not the password');
    await tester.tap(find.text('Unlock'));
    await settle(tester);

    expect(find.text('That password is not correct.'), findsOneWidget);
    expect(find.text('Unlock vault'), findsOneWidget, reason: 'dialog stays open');
    expect(results, isEmpty, reason: 'dialog has not returned yet');
  });

  testWidgets('the correct password unlocks and closes with true', (tester) async {
    final results = await pumpDialog(tester);

    await tester.enterText(find.byType(TextField), _correctPassword);
    await tester.tap(find.text('Unlock'));
    await settle(tester);

    expect(find.text('Unlock vault'), findsNothing, reason: 'dialog closed');
    expect(results, [true]);
  });

  testWidgets('"Skip for now" closes the dialog and returns false', (tester) async {
    final results = await pumpDialog(tester);

    await tester.tap(find.text('Skip for now'));
    await settle(tester);

    expect(find.text('Unlock vault'), findsNothing);
    expect(results, [false]);
  });

  testWidgets('per-project variant renders book-specific copy', (tester) async {
    final project = Project(
      id: 'p1',
      title: 'The Long Winter',
      author: 'Test',
      folderName: 'the-long-winter',
      created: DateTime(2026, 1, 1),
      modified: DateTime(2026, 1, 1),
    );
    final results = await pumpDialog(tester, forProject: project);

    expect(find.text("Unlock this book's vault"), findsOneWidget);
    expect(find.textContaining('The Long Winter'), findsOneWidget);

    // Skip is handled entirely by the dialog (no VaultActions call needed).
    await tester.tap(find.text('Skip for now'));
    await settle(tester);
    expect(results, [false]);
  });
}
