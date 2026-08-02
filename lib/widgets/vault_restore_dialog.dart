import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../models/project.dart';
import '../state/library_provider.dart';
import '../state/vault_provider.dart';

final _generationFormat = DateFormat('d MMM yyyy, HH:mm');
final _folderStampFormat = DateFormat('yyyy-MM-dd HH-mm');

Future<void> showVaultRestoreDialog(BuildContext context, Project project) =>
    showDialog<void>(
      context: context,
      builder: (_) => _VaultRestoreDialog(project: project),
    );

/// Restores a vault generation into a **new** project folder beside the
/// original rather than overwriting it. A restore is a recovery action taken
/// when something already looks wrong, which is exactly when destroying the
/// current state would be worst — so the user gets both copies and decides
/// which to keep.
class _VaultRestoreDialog extends ConsumerStatefulWidget {
  const _VaultRestoreDialog({required this.project});

  final Project project;

  @override
  ConsumerState<_VaultRestoreDialog> createState() =>
      _VaultRestoreDialogState();
}

class _VaultRestoreDialogState extends ConsumerState<_VaultRestoreDialog> {
  final _password = TextEditingController();
  File? _selected;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final generation = _selected;
    if (generation == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final libraryRoot = await ref.read(libraryServiceProvider).libraryRoot();
      final targetDir = Directory(
        _uniquePath(
          libraryRoot,
          '${widget.project.folderName} (restored ${_folderStampFormat.format(DateTime.now())})',
        ),
      );

      await ref
          .read(vaultServiceProvider)
          .restoreVault(
            vaultFile: generation,
            targetDir: targetDir,
            password: _password.text,
          );

      ref.invalidate(projectListProvider);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restored to "${p.basename(targetDir.path)}".'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  /// Same collision-avoidance shape as LibraryService's folder naming: append
  /// a counter rather than overwriting an existing folder.
  String _uniquePath(Directory root, String baseName) {
    var candidate = baseName;
    var suffix = 1;
    while (Directory(p.join(root.path, candidate)).existsSync()) {
      suffix++;
      candidate = '$baseName ($suffix)';
    }
    return p.join(root.path, candidate);
  }

  @override
  Widget build(BuildContext context) {
    final generationsAsync = ref.watch(
      vaultGenerationsProvider(widget.project),
    );

    return AlertDialog(
      title: Text('Restore ${widget.project.title}'),
      content: SizedBox(
        width: 460,
        child: generationsAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (err, stack) => Text('Could not list backups: $err'),
          data: (generations) {
            if (generations.isEmpty) {
              return const Text('This project has no vault backups yet.');
            }
            _selected ??= generations.first;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Choose a backup to restore:'),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: RadioGroup<File>(
                      groupValue: _selected,
                      onChanged: (value) {
                        if (_busy) return;
                        setState(() => _selected = value);
                      },
                      child: Column(
                        children: [
                          for (final generation in generations)
                            RadioListTile<File>(
                              dense: true,
                              value: generation,
                              title: Text(
                                _labelFor(
                                  generation,
                                  generations.first == generation,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // A plain (unencrypted — see "Back up without a password" in
                // Settings → Vault) generation needs no password at all, and
                // asking for one would just be confusing — checked async per
                // selection since it means opening the file's header.
                FutureBuilder<bool>(
                  future: ref
                      .read(vaultServiceProvider)
                      .isEncryptedVault(_selected!),
                  builder: (context, snapshot) {
                    if (snapshot.data == false) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text('This backup is not password-protected.'),
                      );
                    }
                    return TextField(
                      controller: _password,
                      obscureText: true,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Vault password for this backup',
                        helperText:
                            'Backups made before a password change need the old password.',
                        helperMaxLines: 2,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'The backup is restored into a new project folder next to the '
                  'original. Nothing in "${widget.project.title}" is changed.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || _selected == null ? null : _restore,
          child: const Text('Restore'),
        ),
      ],
    );
  }

  String _labelFor(File generation, bool isLatest) {
    final timestamp = vaultGenerationTimestamp(generation);
    final when = timestamp == null
        ? p.basename(generation.path)
        : _generationFormat.format(timestamp);
    return isLatest ? '$when (most recent)' : when;
  }
}
