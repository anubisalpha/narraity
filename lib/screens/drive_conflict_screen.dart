import 'dart:io';

import 'package:flutter/material.dart';

import '../models/project.dart';
import '../services/drive_sync_planner.dart';
import '../services/drive_sync_service.dart';

/// Lists every file that diverged on both sides since the last sync
/// (PLAN.md: "changed on both sides → keep both files ... flagged in-app
/// for manual merge rather than silently overwriting prose") and lets the
/// user pick a resolution per file. A dedicated screen rather than reusing
/// Version History's diff/restore UI — explicit user choice, since Drive
/// conflicts and scene-snapshot history are different kinds of divergence
/// (cross-device vs. same-device-over-time) even though both end up
/// comparing two versions of the same text.
class DriveConflictScreen extends StatefulWidget {
  const DriveConflictScreen({
    super.key,
    required this.project,
    required this.projectDir,
    required this.syncService,
    required this.conflicts,
  });

  final Project project;
  final Directory projectDir;
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
        await widget.syncService.saveConflictCopy(widget.projectDir, conflict.path);
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
      appBar: AppBar(title: Text('${widget.project.title} — Sync Conflicts')),
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
                    busy: _busyPath == conflict.path,
                    onKeepLocal: () => _resolve(
                      conflict,
                      () => widget.syncService.resolveKeepLocal(
                        widget.projectDir,
                        widget.project.folderName,
                        conflict.path,
                      ),
                    ),
                    onKeepDrive: () => _resolve(
                      conflict,
                      () => widget.syncService.resolveKeepRemote(
                        widget.projectDir,
                        widget.project.folderName,
                        conflict.path,
                      ),
                    ),
                    onKeepBoth: () => _resolve(
                      conflict,
                      () => widget.syncService.resolveKeepRemote(
                        widget.projectDir,
                        widget.project.folderName,
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

class _ConflictTile extends StatelessWidget {
  const _ConflictTile({
    required this.conflict,
    required this.busy,
    required this.onKeepLocal,
    required this.onKeepDrive,
    required this.onKeepBoth,
  });

  final SyncConflict conflict;
  final bool busy;
  final VoidCallback onKeepLocal;
  final VoidCallback onKeepDrive;
  final VoidCallback onKeepBoth;

  @override
  Widget build(BuildContext context) {
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
                Expanded(child: Text(conflict.path, style: Theme.of(context).textTheme.titleSmall)),
                if (busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Edited on this device and on Drive since the last sync.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(onPressed: busy ? null : onKeepLocal, child: const Text('Keep this device')),
                OutlinedButton(onPressed: busy ? null : onKeepDrive, child: const Text('Keep Drive')),
                FilledButton.tonal(onPressed: busy ? null : onKeepBoth, child: const Text('Keep both')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
