import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/vault_provider.dart';

/// Asks for the vault password when opening a project with a configured but
/// locked vault. Returns true if it was unlocked, false if the user skipped.
///
/// Skipping is deliberately allowed and harmless: writing continues normally,
/// new history entries are simply unsigned and automatic backups don't run
/// until the vault is unlocked from Settings. Blocking someone out of their own
/// manuscript because they can't remember a backup password would be a far
/// worse failure than an unsigned session.
Future<bool> showVaultUnlockDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => const _VaultUnlockDialog(),
  );
  return result ?? false;
}

class _VaultUnlockDialog extends ConsumerStatefulWidget {
  const _VaultUnlockDialog();

  @override
  ConsumerState<_VaultUnlockDialog> createState() => _VaultUnlockDialogState();
}

class _VaultUnlockDialogState extends ConsumerState<_VaultUnlockDialog> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref.read(vaultStatusProvider.notifier).unlock(_password.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = 'That password is not correct.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Unlock vault'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Unlocking signs new version history and keeps automatic backups '
              'running. You can skip and carry on writing — history stays '
              'unsigned until you unlock from Settings.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              enabled: !_busy,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'Vault password'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Skip for now'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}
