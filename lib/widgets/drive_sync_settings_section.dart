import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../config/drive_oauth_config.dart';
import '../models/project.dart';
import '../screens/drive_conflict_screen.dart';
import '../screens/drive_sync_log_screen.dart';
import '../services/sync_manifest_service.dart';
import '../state/dictation_provider.dart';
import '../state/drive_auto_sync_provider.dart';
import '../state/drive_provider.dart';
import '../state/editor_settings_provider.dart';
import '../state/library_provider.dart';
import '../state/spell_check_provider.dart';
import '../state/theme_provider.dart';
import '../state/thesaurus_provider.dart';
import '../state/tts_settings_provider.dart';
import '../state/vault_provider.dart';

final _lastSyncFormat = DateFormat('d MMM yyyy, HH:mm');

/// Settings body for "Google Drive Sync" — connect/disconnect, then a
/// manual "Sync now" per project, plus two always-present targets that
/// close the "sync only restores manuscripts" gap: Vault backups (disaster
/// recovery — otherwise never leaves the device at all) and App Settings
/// (theme, dictation/spell-check/Read-Aloud preferences, so a new device
/// picks up how the app was set up, not just what was written). Kept
/// deliberately simple for v1: no automatic background sync loop, just the
/// manual action plus an on-foreground check (wired from the shell, not
/// this widget).
class DriveSyncSettingsSection extends ConsumerWidget {
  const DriveSyncSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!DriveOAuthConfig.isConfigured) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Google Drive sync needs an OAuth client ID configured at build time '
            '(--dart-define-from-file=oauth_config.json — see README.md\'s "Google Drive Sync" '
            'section). Not set for this build.',
          ),
        ),
      );
    }

    final status = ref.watch(driveConnectionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (Platform.isWindows) ...[
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This is Narraity\'s own sync, unrelated to the Google Drive desktop app '
                      '(Drive File Stream/Backup and Sync) if you have it installed separately. '
                      'If that app is also watching your Narraity project folder, it can '
                      'occasionally hold a file briefly locked right after a save — most '
                      'noticeable as a short delay when archiving or deleting a project. It\'s '
                      'harmless and Narraity retries automatically, but excluding the Narraity '
                      'folder from the Google Drive app\'s sync scope avoids it entirely.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _ConnectionRow(status: status),
          ),
        ),
        if (status == DriveConnectionStatus.signedIn) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text('Automatic Sync', style: Theme.of(context).textTheme.titleSmall),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DriveSyncLogScreen()),
                ),
                icon: const Icon(Icons.history, size: 18),
                label: const Text('Sync Log'),
              ),
            ],
          ),
          const _AutoSyncSettingsCard(),
          const SizedBox(height: 24),
          Card(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SyncTargetTile(
                  title: 'Vault backups',
                  icon: Icons.shield_outlined,
                  folderName: '_Vault',
                  resolveDirectory: (ref) => ref.read(vaultRootProvider.future),
                ),
                _SyncTargetTile(
                  title: 'App settings',
                  icon: Icons.settings_outlined,
                  folderName: '_Settings',
                  resolveDirectory: (ref) async {
                    final settings = ref.read(appSettingsServiceProvider);
                    await settings.exportToFile();
                    return settings.settingsRoot();
                  },
                  onAfterSync: () async {
                    await ref.read(appSettingsServiceProvider).importFromFile();
                    // Reload every provider AppSettingsService knows how to
                    // export/import, so a pulled change from another device
                    // shows up immediately instead of needing a restart.
                    // Kept in sync by hand with reapplyAppSettingsAfterSync
                    // in drive_auto_sync_provider.dart — see that
                    // function's doc comment for why it isn't shared
                    // directly (Ref vs. WidgetRef).
                    ref.invalidate(themeModeProvider);
                    ref.invalidate(dictationLanguageProvider);
                    ref.invalidate(dictationModelSizeProvider);
                    ref.invalidate(spellCheckEnabledProvider);
                    ref.invalidate(thesaurusEnabledProvider);
                    ref.invalidate(ttsSettingsProvider);
                    ref.invalidate(editorSettingsProvider);
                    ref.invalidate(vaultRetentionCountProvider);
                    ref.invalidate(vaultAutoRefreshProvider);
                    ref.invalidate(driveImmediateSyncEnabledProvider);
                    ref.invalidate(driveDailySyncEnabledProvider);
                    ref.invalidate(driveFrequentSyncIntervalProvider);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Projects', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          const _ProjectSyncList(),
        ],
      ],
    );
  }
}

/// Toggles for the three auto-sync mechanisms — all off by default
/// (deliberate, per the user's own preference: this is new automatic
/// network activity that didn't exist before, so it's opt-in). Daily and
/// "more frequent" are independent, not mutually exclusive — enabling both
/// just means whichever fires more often effectively drives it, which is
/// harmless.
class _AutoSyncSettingsCard extends ConsumerWidget {
  const _AutoSyncSettingsCard();

  static const _frequentOptions = [0, 5, 15, 30, 60];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final immediate = ref.watch(driveImmediateSyncEnabledProvider);
    final daily = ref.watch(driveDailySyncEnabledProvider);
    final frequentMinutes = ref.watch(driveFrequentSyncIntervalProvider);

    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            title: const Text('Sync immediately after saving'),
            subtitle: const Text(
              'Watches the open project and syncs just the changed file, right after it saves.',
            ),
            value: immediate,
            onChanged: (value) =>
                ref.read(driveImmediateSyncEnabledProvider.notifier).set(value),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Daily sync'),
            subtitle: const Text('A full sync + reconciliation check at least once a day.'),
            value: daily,
            onChanged: (value) => ref.read(driveDailySyncEnabledProvider.notifier).set(value),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('More frequent sync'),
            subtitle: const Text('An additional full sync on a shorter interval.'),
            trailing: DropdownButton<int>(
              value: frequentMinutes,
              items: [
                for (final minutes in _frequentOptions)
                  DropdownMenuItem(
                    value: minutes,
                    child: Text(minutes == 0 ? 'Off' : 'Every $minutes min'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  ref.read(driveFrequentSyncIntervalProvider.notifier).set(value);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionRow extends ConsumerStatefulWidget {
  const _ConnectionRow({required this.status});
  final DriveConnectionStatus status;

  @override
  ConsumerState<_ConnectionRow> createState() => _ConnectionRowState();
}

class _ConnectionRowState extends ConsumerState<_ConnectionRow> {
  String? _error;

  Future<void> _connect() async {
    setState(() => _error = null);
    final error = await ref.read(driveConnectionProvider.notifier).connect();
    if (mounted) setState(() => _error = error);
  }

  Future<void> _disconnect() => ref.read(driveConnectionProvider.notifier).disconnect();

  void _cancel() => ref.read(driveConnectionProvider.notifier).cancelConnect();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              widget.status == DriveConnectionStatus.signedIn
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              color: widget.status == DriveConnectionStatus.signedIn ? Colors.green : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(switch (widget.status) {
                DriveConnectionStatus.signedIn => 'Connected to Google Drive.',
                DriveConnectionStatus.signingIn =>
                  'Waiting for sign-in in your browser...',
                DriveConnectionStatus.signedOut => 'Not connected.',
                DriveConnectionStatus.unknown => 'Checking connection...',
              }),
            ),
            if (widget.status == DriveConnectionStatus.signingIn) ...[
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              TextButton(onPressed: _cancel, child: const Text('Cancel')),
            ] else if (widget.status == DriveConnectionStatus.signedIn)
              OutlinedButton(onPressed: _disconnect, child: const Text('Disconnect'))
            else
              FilledButton(onPressed: _connect, child: const Text('Connect')),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }
}

class _ProjectSyncList extends ConsumerWidget {
  const _ProjectSyncList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectListProvider);
    return projectsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Text('Could not list projects: $err'),
      data: (projects) => projects.isEmpty
          ? const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No projects yet.'),
              ),
            )
          : Card(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final project in projects)
                    _SyncTargetTile(
                      title: project.title,
                      icon: Icons.book_outlined,
                      folderName: project.folderName,
                      resolveDirectory: (ref) =>
                          projectDirectory(ref.read(libraryServiceProvider), project),
                    ),
                ],
              ),
            ),
    );
  }
}

/// One row: a manual "Sync now" for a single Drive sync target — a project,
/// the Vault backups folder, or the consolidated app-settings file. Not
/// tied to [Project] specifically so all three can share the same
/// sync/status/conflict-navigation logic.
class _SyncTargetTile extends ConsumerStatefulWidget {
  const _SyncTargetTile({
    required this.title,
    required this.icon,
    required this.folderName,
    required this.resolveDirectory,
    this.onAfterSync,
  });

  final String title;
  final IconData icon;
  final String folderName;
  final Future<Directory> Function(WidgetRef ref) resolveDirectory;

  /// Called after a successful sync (regardless of whether conflicts were
  /// found) — used by the App Settings tile to re-apply a possibly-updated
  /// settings file back into the live providers.
  final Future<void> Function()? onAfterSync;

  @override
  ConsumerState<_SyncTargetTile> createState() => _SyncTargetTileState();
}

class _SyncTargetTileState extends ConsumerState<_SyncTargetTile> {
  bool _syncing = false;
  String? _error;
  DateTime? _lastSyncTime;

  @override
  void initState() {
    super.initState();
    _loadLastSyncTime();
  }

  Future<void> _loadLastSyncTime() async {
    final dir = await widget.resolveDirectory(ref);
    final manifest = await SyncManifestService().read(dir);
    if (mounted) setState(() => _lastSyncTime = manifest.lastSyncTime);
  }

  Future<void> _sync() async {
    setState(() {
      _syncing = true;
      _error = null;
    });
    try {
      final service = await ref.read(driveSyncServiceProvider.future);
      final dir = await widget.resolveDirectory(ref);
      final result = await service.sync(dir, widget.folderName);
      if (!mounted) return;
      setState(() => _lastSyncTime = DateTime.now());

      if (result.conflicts.isNotEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DriveConflictScreen(
              title: widget.title,
              folderName: widget.folderName,
              directory: dir,
              syncService: service,
              conflicts: result.conflicts,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Synced "${widget.title}": '
              '${result.uploaded.length} uploaded, ${result.downloaded.length} downloaded.',
            ),
          ),
        );
      }

      await widget.onAfterSync?.call();
    } catch (error) {
      if (mounted) setState(() => _error = 'Sync failed: $error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(widget.icon),
      title: Text(widget.title),
      subtitle: Text(
        _error ??
            (_lastSyncTime == null
                ? 'Never synced'
                : 'Last synced ${_lastSyncFormat.format(_lastSyncTime!)}'),
        style: _error != null ? TextStyle(color: Theme.of(context).colorScheme.error) : null,
      ),
      trailing: _syncing
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : TextButton(onPressed: _sync, child: const Text('Sync now')),
    );
  }
}
