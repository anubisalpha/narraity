import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/archived_project.dart';
import '../state/library_provider.dart';

/// Archived and soft-deleted projects — each one is a `.zip` of its whole
/// former folder tree under the library's reserved `_Archived`/`_Deleted`
/// folders (see `LibraryService`). Two tabs, same list UI, differing only
/// in which reserved folder and provider they read from — deletion here is
/// deliberately not permanent (see the Library screen's delete confirmation
/// dialog): restoring is the only action offered, since a user who wants a
/// project truly gone removes the zip themselves from the file system.
class ArchivedProjectsScreen extends StatelessWidget {
  const ArchivedProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Archived & Deleted'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Archived'),
              Tab(text: 'Deleted'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _RecordList(kind: _RecordListKind.archived),
            _RecordList(kind: _RecordListKind.deleted),
          ],
        ),
      ),
    );
  }
}

enum _RecordListKind { archived, deleted }

class _RecordList extends ConsumerWidget {
  const _RecordList({required this.kind});

  final _RecordListKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = kind == _RecordListKind.archived
        ? archivedProjectsProvider
        : deletedProjectsProvider;
    final recordsAsync = ref.watch(provider);

    return recordsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Could not load: $error')),
      data: (records) {
        if (records.isEmpty) {
          return Center(
            child: Text(
              kind == _RecordListKind.archived ? 'No archived projects.' : 'No deleted projects.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }
        return ListView.builder(
          itemCount: records.length,
          itemBuilder: (context, index) {
            final record = records[index];
            return ListTile(
              title: Text(record.title),
              subtitle: Text(
                [
                  if (record.author != null) record.author!,
                  '${kind == _RecordListKind.archived ? "Archived" : "Deleted"} '
                      '${DateFormat.yMMMd().add_jm().format(record.archivedAt)}',
                ].join(' · '),
              ),
              trailing: FilledButton.tonal(
                onPressed: () => _restore(context, ref, record),
                child: const Text('Restore'),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref, ArchivedProject record) async {
    final libraryService = ref.read(libraryServiceProvider);
    if (kind == _RecordListKind.archived) {
      await libraryService.restoreArchived(record);
      ref.invalidate(archivedProjectsProvider);
    } else {
      await libraryService.restoreDeleted(record);
      ref.invalidate(deletedProjectsProvider);
    }
    ref.invalidate(projectListProvider);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${record.title}" restored to your library')),
      );
    }
  }
}
