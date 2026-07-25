import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/project.dart';
import '../state/library_provider.dart';
import '../state/vault_provider.dart';
import 'vault_restore_dialog.dart';

/// Minimum vault password length. Short enough not to be obnoxious, long
/// enough that Argon2id's cost actually buys something.
const _minPasswordLength = 8;

final _generationFormat = DateFormat('d MMM yyyy, HH:mm');

/// Settings body for "Backup & Vault" — the UI over VaultService and
/// HistorySigningKeyManager. Renders one of three states: no password set
/// yet, password set but locked this session, or unlocked.
class VaultSettingsSection extends ConsumerWidget {
  const VaultSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(vaultStatusProvider);

    return statusAsync.when(
      loading: () => const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: CircularProgressIndicator(),
      )),
      error: (err, stack) => Text('Could not read vault state: $err'),
      data: (status) => switch (status) {
        VaultStatus.notConfigured => const _SetupCard(),
        VaultStatus.locked => const _UnlockCard(),
        VaultStatus.unlocked => const _UnlockedBody(),
      },
    );
  }
}

class _SetupCard extends ConsumerStatefulWidget {
  const _SetupCard();

  @override
  ConsumerState<_SetupCard> createState() => _SetupCardState();
}

class _SetupCardState extends ConsumerState<_SetupCard> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _password.text;
    if (password.length < _minPasswordLength) {
      setState(() => _error = 'Use at least $_minPasswordLength characters.');
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = 'The two passwords do not match.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(vaultStatusProvider.notifier).setup(password);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'A vault is a single encrypted backup file per project, kept '
                  'separately from your working files. The same password also '
                  'signs your version history, so tampering or corruption can '
                  'be detected.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  obscureText: true,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: 'Vault password'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  enabled: !_busy,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(labelText: 'Confirm password'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Set up vault password'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'There is no way to recover this password. Without it, vault '
                    'backups cannot be opened by anyone — including you. Write it '
                    'down somewhere safe.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _UnlockCard extends ConsumerStatefulWidget {
  const _UnlockCard();

  @override
  ConsumerState<_UnlockCard> createState() => _UnlockCardState();
}

class _UnlockCardState extends ConsumerState<_UnlockCard> {
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
    try {
      final ok = await ref.read(vaultStatusProvider.notifier).unlock(_password.text);
      if (!ok && mounted) setState(() => _error = 'That password is not correct.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lock_outline),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Vault is locked. Writing still works normally, but new '
                    'history entries are unsigned and backups will not run '
                    'until you unlock.',
                  ),
                ),
              ],
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
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Unlock'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnlockedBody extends ConsumerWidget {
  const _UnlockedBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final retention = ref.watch(vaultRetentionCountProvider);
    final autoRefresh = ref.watch(vaultAutoRefreshProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.verified_user_outlined, color: Colors.green),
            title: const Text('Vault unlocked'),
            subtitle: const Text('History entries are signed and verified; backups can run.'),
            trailing: TextButton(
              onPressed: () => ref.read(vaultStatusProvider.notifier).lock(),
              child: const Text('Lock'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: autoRefresh,
                  onChanged: (value) => ref.read(vaultAutoRefreshProvider.notifier).set(value),
                  title: const Text('Back up automatically'),
                  subtitle: const Text(
                    'Refreshes the open project\'s vault periodically and when you close it.',
                  ),
                ),
                const Divider(height: 24),
                Text('Generations kept per project: $retention',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                const Text(
                  'Older backups are pruned beyond this count. Keeping several '
                  'means a longer window to notice a problem before the last '
                  'good backup rotates out.',
                ),
                Slider(
                  value: retention.toDouble(),
                  min: VaultRetentionNotifier.minCount.toDouble(),
                  max: VaultRetentionNotifier.maxCount.toDouble(),
                  divisions: VaultRetentionNotifier.maxCount - VaultRetentionNotifier.minCount,
                  label: '$retention',
                  onChanged: (value) =>
                      ref.read(vaultRetentionCountProvider.notifier).set(value.round()),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Backups', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        const _ProjectBackupList(),
        const SizedBox(height: 24),
        Text('Password', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.password_outlined),
            title: const Text('Change vault password'),
            subtitle: const Text(
              'Re-signs all version history with the new password. Vault files '
              'made before the change still open with the old one.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showChangeVaultPasswordDialog(context),
          ),
        ),
      ],
    );
  }
}

class _ProjectBackupList extends ConsumerWidget {
  const _ProjectBackupList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectListProvider);

    return Card(
      child: projectsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (err, stack) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Could not list projects: $err'),
        ),
        data: (projects) => projects.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No projects yet.'),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final project in projects) _ProjectBackupTile(project: project),
                ],
              ),
      ),
    );
  }
}

class _ProjectBackupTile extends ConsumerStatefulWidget {
  const _ProjectBackupTile({required this.project});

  final Project project;

  @override
  ConsumerState<_ProjectBackupTile> createState() => _ProjectBackupTileState();
}

class _ProjectBackupTileState extends ConsumerState<_ProjectBackupTile> {
  bool _busy = false;

  Future<void> _backupNow() async {
    setState(() => _busy = true);
    try {
      await ref.read(vaultActionsProvider).refreshProject(widget.project);
      ref.invalidate(vaultGenerationsProvider(widget.project));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backed up ${widget.project.title}.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final generationsAsync = ref.watch(vaultGenerationsProvider(widget.project));

    return ListTile(
      leading: const Icon(Icons.shield_outlined),
      title: Text(widget.project.title),
      subtitle: Text(generationsAsync.when(
        loading: () => 'Checking backups…',
        error: (err, stack) => 'Could not read backups',
        data: (generations) {
          if (generations.isEmpty) return 'No backups yet';
          final latest = vaultGenerationTimestamp(generations.first);
          final when = latest == null ? 'unknown time' : _generationFormat.format(latest);
          final count = generations.length;
          return 'Latest $when · $count generation${count == 1 ? '' : 's'}';
        },
      )),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => showVaultRestoreDialog(context, widget.project),
            child: const Text('Restore…'),
          ),
          IconButton(
            tooltip: 'Back up now',
            icon: _busy
                ? const SizedBox(
                    height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.backup_outlined),
            onPressed: _busy ? null : _backupNow,
          ),
        ],
      ),
    );
  }
}

Future<void> showChangeVaultPasswordDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _ChangePasswordDialog());

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  String? _progress;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_next.text.length < _minPasswordLength) {
      setState(() => _error = 'Use at least $_minPasswordLength characters.');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = 'The two new passwords do not match.');
      return;
    }

    setState(() {
      _error = null;
      _progress = 'Starting…';
    });
    try {
      await ref.read(vaultActionsProvider).changePassword(
        oldPassword: _current.text,
        newPassword: _next.text,
        onProgress: (status) {
          if (mounted) setState(() => _progress = status);
        },
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vault password changed and history re-signed.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _progress != null;

    return AlertDialog(
      title: const Text('Change vault password'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _current,
              obscureText: true,
              autofocus: true,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _next,
              obscureText: true,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'Confirm new password'),
            ),
            const SizedBox(height: 16),
            Text(
              'Every version-history entry in every project is re-signed with the '
              'new password, and a fresh backup is made. Existing vault files stay '
              'tied to the old password.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(_progress!),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : _submit,
          child: const Text('Change password'),
        ),
      ],
    );
  }
}
