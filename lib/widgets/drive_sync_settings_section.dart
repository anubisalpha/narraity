import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../config/drive_oauth_config.dart';
import '../models/project.dart';
import '../screens/drive_conflict_screen.dart';
import '../services/sync_manifest_service.dart';
import '../state/drive_provider.dart';
import '../state/library_provider.dart';

final _lastSyncFormat = DateFormat('d MMM yyyy, HH:mm');

/// Settings body for "Google Drive Sync" — connect/disconnect, then a
/// per-project "Sync now" list. Kept deliberately simple for v1: no
/// automatic background sync loop, just the manual action plus an
/// on-foreground check (wired from the shell, not this widget).
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _ConnectionRow(status: status),
          ),
        ),
        if (status == DriveConnectionStatus.signedIn) ...[
          const SizedBox(height: 24),
          Text('Projects', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          const _ProjectSyncList(),
        ],
      ],
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
            if (widget.status == DriveConnectionStatus.signingIn)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else if (widget.status == DriveConnectionStatus.signedIn)
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
                  for (final project in projects) _ProjectSyncTile(project: project),
                ],
              ),
            ),
    );
  }
}

class _ProjectSyncTile extends ConsumerStatefulWidget {
  const _ProjectSyncTile({required this.project});
  final Project project;

  @override
  ConsumerState<_ProjectSyncTile> createState() => _ProjectSyncTileState();
}

class _ProjectSyncTileState extends ConsumerState<_ProjectSyncTile> {
  bool _syncing = false;
  String? _error;
  DateTime? _lastSyncTime;

  @override
  void initState() {
    super.initState();
    _loadLastSyncTime();
  }

  Future<void> _loadLastSyncTime() async {
    final dir = await projectDirectory(ref.read(libraryServiceProvider), widget.project);
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
      final dir = await projectDirectory(ref.read(libraryServiceProvider), widget.project);
      final result = await service.sync(dir, widget.project.folderName);
      if (!mounted) return;
      setState(() => _lastSyncTime = DateTime.now());

      if (result.conflicts.isNotEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DriveConflictScreen(
              project: widget.project,
              projectDir: dir,
              syncService: service,
              conflicts: result.conflicts,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Synced "${widget.project.title}": '
              '${result.uploaded.length} uploaded, ${result.downloaded.length} downloaded.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Sync failed: $error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.book_outlined),
      title: Text(widget.project.title),
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
