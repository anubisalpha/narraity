import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/sync_log_entry.dart';
import '../services/drive_sync_log_service.dart';

final _timestampFormat = DateFormat('d MMM, HH:mm:ss');

/// Read-only activity log for Drive sync — every manual, immediate, or
/// periodic sync attempt, most recent first. Exists so "is this actually
/// syncing?" has a concrete answer beyond a snackbar that's already gone.
class DriveSyncLogScreen extends StatefulWidget {
  const DriveSyncLogScreen({super.key});

  @override
  State<DriveSyncLogScreen> createState() => _DriveSyncLogScreenState();
}

class _DriveSyncLogScreenState extends State<DriveSyncLogScreen> {
  final _service = DriveSyncLogService();
  List<SyncLogEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _service.readRecent();
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _clear() async {
    await _service.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Log'),
        actions: [
          IconButton(
            tooltip: 'Clear log',
            icon: const Icon(Icons.delete_outline),
            onPressed: entries == null || entries.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
              ? const Center(child: Text('No sync activity recorded yet.'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) => _LogTile(entry: entries[index]),
                ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});
  final SyncLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final hasError = entry.error != null;
    return ListTile(
      leading: Icon(
        hasError
            ? Icons.error_outline
            : entry.conflicts > 0
                ? Icons.warning_amber_outlined
                : entry.hadAnyChange
                    ? Icons.cloud_done_outlined
                    : Icons.check_circle_outline,
        color: hasError
            ? Theme.of(context).colorScheme.error
            : entry.conflicts > 0
                ? Colors.amber
                : null,
      ),
      title: Text(entry.targetTitle),
      subtitle: Text(
        hasError
            ? entry.error!
            : entry.hadAnyChange
                ? [
                    if (entry.uploaded > 0) '${entry.uploaded} uploaded',
                    if (entry.downloaded > 0) '${entry.downloaded} downloaded',
                    if (entry.deletedLocal > 0) '${entry.deletedLocal} deleted locally',
                    if (entry.deletedRemote > 0) '${entry.deletedRemote} deleted on Drive',
                    if (entry.conflicts > 0) '${entry.conflicts} conflict(s)',
                  ].join(', ')
                : 'Nothing to sync',
        style: hasError ? TextStyle(color: Theme.of(context).colorScheme.error) : null,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(_timestampFormat.format(entry.timestamp), style: Theme.of(context).textTheme.labelSmall),
          Text(entry.trigger.name, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
