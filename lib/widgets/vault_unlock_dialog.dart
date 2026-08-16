import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../state/vault_provider.dart';

/// Asks for the vault password when opening a project with a configured but
/// locked vault. Returns true if it was unlocked, false if the user skipped.
///
/// Pass [project] to unlock that project's *own* vault password (the opt-in
/// per-project override) rather than the library-wide one — the copy and the
/// unlock call switch accordingly.
///
/// Skipping is deliberately allowed and harmless: writing continues normally,
/// new history entries are simply unsigned and automatic backups don't run
/// until the vault is unlocked from Settings. Blocking someone out of their own
/// manuscript because they can't remember a backup password would be a far
/// worse failure than an unsigned session.
Future<bool> showVaultUnlockDialog(BuildContext context, {Project? project}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _VaultUnlockDialog(project: project),
  );
  return result ?? false;
}

class _VaultUnlockDialog extends ConsumerStatefulWidget {
  const _VaultUnlockDialog({this.project});

  final Project? project;

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
    final project = widget.project;
    final ok = project != null
        ? await ref.read(vaultActionsProvider).unlockProject(project, _password.text)
        : await ref.read(vaultStatusProvider.notifier).unlock(_password.text);
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
    final project = widget.project;
    return AlertDialog(
      title: Text(project != null ? 'Unlock this book\'s vault' : 'Unlock vault'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              project != null
                  ? '"${project.title}" has its own vault password. Unlocking '
                      'signs its new version history and keeps its automatic '
                      'backups running. You can skip and carry on writing.'
                  : 'Unlocking signs new version history and keeps automatic '
                      'backups running. You can skip and carry on writing — '
                      'history stays unsigned until you unlock from Settings.',
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
