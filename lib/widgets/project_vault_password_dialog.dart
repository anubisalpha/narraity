import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../services/vault_service.dart';
import '../state/vault_provider.dart';

/// Minimum vault password length — matches `vault_settings_section.dart`.
const _minPasswordLength = 8;

/// Manages [project]'s *own* vault password (the opt-in per-project override):
/// give a book its own password separate from the library one, change it, or
/// hand it back to the library password. The heavy lifting — re-signing scene
/// history onto the new key — lives in [VaultActions]; this is just the form.
Future<void> showProjectVaultPasswordDialog(BuildContext context, Project project) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ProjectVaultPasswordDialog(project: project),
  );
}

enum _View { overview, setNew, change }

class _ProjectVaultPasswordDialog extends ConsumerStatefulWidget {
  const _ProjectVaultPasswordDialog({required this.project});

  final Project project;

  @override
  ConsumerState<_ProjectVaultPasswordDialog> createState() =>
      _ProjectVaultPasswordDialogState();
}

class _ProjectVaultPasswordDialogState
    extends ConsumerState<_ProjectVaultPasswordDialog> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  _View _view = _View.overview;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// Validates the new-password pair shared by the set and change flows.
  String? _validateNewPassword() {
    if (_password.text.length < _minPasswordLength) {
      return 'Use at least $_minPasswordLength characters.';
    }
    if (_password.text != _confirm.text) {
      return 'The two passwords do not match.';
    }
    return null;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } on VaultOpenException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goTo(_View view) {
    setState(() {
      _view = view;
      _error = null;
      _current.clear();
      _password.clear();
      _confirm.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final actions = ref.read(vaultActionsProvider);
    return AlertDialog(
      title: Text('Vault password — ${widget.project.title}'),
      content: SizedBox(width: 420, child: _buildContent(actions)),
    );
  }

  Widget _buildContent(VaultActions actions) {
    switch (_view) {
      case _View.overview:
        return _buildOverview(actions);
      case _View.setNew:
        return _buildSetOrChange(
          intro: 'Choose a password for this book. It\'s separate from your '
              'library password, and — like the library one — it can\'t be '
              'recovered if you forget it.',
          confirmLabel: 'Set password',
          onConfirm: () {
            final err = _validateNewPassword();
            if (err != null) {
              setState(() => _error = err);
              return;
            }
            _run(() => actions.setProjectPassword(widget.project, _password.text));
          },
        );
      case _View.change:
        return _buildSetOrChange(
          intro: 'Enter the current password for this book, then choose a new one.',
          withCurrent: true,
          confirmLabel: 'Change password',
          onConfirm: () {
            final err = _validateNewPassword();
            if (err != null) {
              setState(() => _error = err);
              return;
            }
            _run(() => actions.changeProjectPassword(
                  widget.project,
                  _current.text,
                  _password.text,
                ));
          },
        );
    }
  }

  Widget _buildOverview(VaultActions actions) {
    final hasOwnAsync = ref.watch(projectHasOwnPasswordProvider(widget.project));
    return hasOwnAsync.when(
      loading: () => const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Text('Could not read vault state: $err'),
      data: (hasOwn) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasOwn
                ? 'This book uses its own vault password, separate from the rest '
                    'of your library.'
                : 'This book is backed up and its version history is signed with '
                    'your library-wide vault password. You can give it its own '
                    'password instead.',
          ),
          const SizedBox(height: 20),
          if (!hasOwn)
            FilledButton.icon(
              onPressed: _busy ? null : () => _goTo(_View.setNew),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Give this book its own password'),
            )
          else ...[
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _goTo(_View.change),
              icon: const Icon(Icons.password),
              label: const Text('Change this book\'s password'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _confirmRemove(actions),
              icon: const Icon(Icons.link),
              label: const Text('Use the library password instead'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetOrChange({
    required String intro,
    required String confirmLabel,
    required VoidCallback onConfirm,
    bool withCurrent = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(intro),
        const SizedBox(height: 16),
        if (withCurrent) ...[
          TextField(
            controller: _current,
            obscureText: true,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Current password'),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _password,
          obscureText: true,
          autofocus: true,
          enabled: !_busy,
          decoration: const InputDecoration(labelText: 'New password'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _confirm,
          obscureText: true,
          enabled: !_busy,
          onSubmitted: (_) => onConfirm(),
          decoration: const InputDecoration(labelText: 'Confirm new password'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy ? null : () => _goTo(_View.overview),
              child: const Text('Back'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : onConfirm,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(confirmLabel),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmRemove(VaultActions actions) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use the library password?'),
        content: const Text(
          'This book\'s version history will be re-signed with your library '
          'vault password, and its own password removed. Both this book\'s '
          'vault and your library vault need to be unlocked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Switch to library password'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(() => actions.removeProjectPassword(widget.project));
    }
  }
}
