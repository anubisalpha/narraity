import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../services/drive_sync_planner.dart';
import '../services/drive_sync_service.dart';
import '../widgets/inline_text_diff.dart';

final _timestampFormat = DateFormat.yMMMd().add_jm();

/// Lists every file that diverged on both sides since the last sync
/// (PLAN.md: "changed on both sides → keep both files ... flagged in-app
/// for manual merge rather than silently overwriting prose") and lets the
/// user pick a resolution per file. A dedicated screen rather than reusing
/// Version History's diff/restore UI — explicit user choice, since Drive
/// conflicts and scene-snapshot history are different kinds of divergence
/// (cross-device vs. same-device-over-time) even though both end up
/// comparing two versions of the same text.
///
/// Not project-specific — [folderName]/[directory] identify whatever sync
/// target this conflict came from (a project, the Vault backups, or the
/// consolidated app settings file), so one screen serves all of them.
class DriveConflictScreen extends StatefulWidget {
  const DriveConflictScreen({
    super.key,
    required this.title,
    required this.folderName,
    required this.directory,
    required this.syncService,
    required this.conflicts,
  });

  final String title;
  final String folderName;
  final Directory directory;
  final DriveSyncService syncService;
  final List<SyncConflict> conflicts;

  @override
  State<DriveConflictScreen> createState() => _DriveConflictScreenState();
}

class _DriveConflictScreenState extends State<DriveConflictScreen> {
  late List<SyncConflict> _remaining = List.of(widget.conflicts);
  String? _busyPath;
  String? _error;

  Future<void> _resolve(
    SyncConflict conflict,
    Future<void> Function() action, {
    bool saveConflictCopyFirst = false,
  }) async {
    setState(() {
      _busyPath = conflict.path;
      _error = null;
    });
    try {
      if (saveConflictCopyFirst) {
        await widget.syncService.saveConflictCopy(widget.directory, conflict.path);
      }
      await action();
      if (!mounted) return;
      setState(() {
        _remaining = _remaining.where((c) => c.path != conflict.path).toList();
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not resolve "${conflict.path}": $error');
    } finally {
      if (mounted) setState(() => _busyPath = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.title} — Sync Conflicts')),
      body: _remaining.isEmpty
          ? const Center(child: Text('No conflicts left to resolve.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                for (final conflict in _remaining)
                  _ConflictTile(
                    conflict: conflict,
                    directory: widget.directory,
                    syncService: widget.syncService,
                    busy: _busyPath == conflict.path,
                    onKeepLocal: () => _resolve(
                      conflict,
                      () => widget.syncService.resolveKeepLocal(
                        widget.directory,
                        widget.folderName,
                        conflict.path,
                      ),
                    ),
                    onKeepDrive: () => _resolve(
                      conflict,
                      () => widget.syncService.resolveKeepRemote(
                        widget.directory,
                        widget.folderName,
                        conflict.path,
                      ),
                    ),
                    onKeepBoth: () => _resolve(
                      conflict,
                      () => widget.syncService.resolveKeepRemote(
                        widget.directory,
                        widget.folderName,
                        conflict.path,
                      ),
                      saveConflictCopyFirst: true,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ConflictTile extends StatefulWidget {
  const _ConflictTile({
    required this.conflict,
    required this.directory,
    required this.syncService,
    required this.busy,
    required this.onKeepLocal,
    required this.onKeepDrive,
    required this.onKeepBoth,
  });

  final SyncConflict conflict;
  final Directory directory;
  final DriveSyncService syncService;
  final bool busy;
  final VoidCallback onKeepLocal;
  final VoidCallback onKeepDrive;
  final VoidCallback onKeepBoth;

  @override
  State<_ConflictTile> createState() => _ConflictTileState();
}

class _ConflictTileState extends State<_ConflictTile> {
  bool _showDiff = false;

  /// Fetched lazily on first expand and cached — `conflictPreview` downloads
  /// the Drive side, so it shouldn't run for every conflict up front, nor
  /// re-run on each rebuild while the diff stays open.
  Future<({String? local, String? drive})>? _previewFuture;

  /// The local file's own filesystem mtime — a plain `statSync` on one small
  /// file, cheap enough to call straight from `build` for a conflict list
  /// that's realistically a handful of entries, not thousands.
  DateTime? get _localModified {
    final file = File(
      p.joinAll([widget.directory.path, ...p.posix.split(widget.conflict.path)]),
    );
    try {
      return file.statSync().modified;
    } on FileSystemException {
      return null;
    }
  }

  void _toggleDiff() {
    setState(() {
      _showDiff = !_showDiff;
      _previewFuture ??=
          widget.syncService.conflictPreview(widget.directory, widget.conflict);
    });
  }

  @override
  Widget build(BuildContext context) {
    final localModified = _localModified;
    final driveModified = widget.conflict.driveModifiedTime;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.conflict.path, style: theme.textTheme.titleSmall)),
                if (widget.busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Edited on this device and on Drive since the last sync.'),
            const SizedBox(height: 8),
            Text(
              'This device: ${localModified != null ? _timestampFormat.format(localModified.toLocal()) : 'unknown'}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              'Drive: ${driveModified != null ? _timestampFormat.format(driveModified.toLocal()) : 'unknown'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _toggleDiff,
                icon: Icon(_showDiff ? Icons.expand_less : Icons.difference_outlined, size: 18),
                label: Text(_showDiff ? 'Hide changes' : 'Show what changed'),
              ),
            ),
            if (_showDiff) _buildDiff(theme),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(onPressed: widget.busy ? null : widget.onKeepLocal, child: const Text('Keep this device')),
                OutlinedButton(onPressed: widget.busy ? null : widget.onKeepDrive, child: const Text('Keep Drive')),
                FilledButton.tonal(onPressed: widget.busy ? null : widget.onKeepBoth, child: const Text('Keep both')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiff(ThemeData theme) {
    return FutureBuilder<({String? local, String? drive})>(
      future: _previewFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Could not load a preview: ${snapshot.error}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          );
        }
        final local = snapshot.data?.local;
        final drive = snapshot.data?.drive;
        if (local == null && drive == null) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'This is a binary file (an image or a zipped archive) — no text '
              'preview available.',
              style: theme.textTheme.bodySmall,
            ),
          );
        }
        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Green = added on Drive · red strikethrough = only on this device',
                style: theme.textTheme.labelSmall,
              ),
              const SizedBox(height: 6),
              Expanded(
                child: SingleChildScrollView(
                  // from = local, to = Drive: insertions are what Drive has
                  // that this device doesn't, deletions the reverse.
                  child: InlineTextDiff(from: local ?? '', to: drive ?? ''),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
