import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/drive_restore_service.dart';
import '../state/drive_provider.dart';
import '../state/library_provider.dart';

/// Lists project folders that exist on Drive but were never pulled down to
/// this device (a fresh install, or a project made on another device) and
/// lets the user restore each one — see `drive_restore_service.dart` for why
/// ordinary "Sync All Now" never surfaces these on its own.
class RestoreFromDriveScreen extends ConsumerWidget {
  const RestoreFromDriveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(driveConnectionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Restore from Drive'),
        actions: [
          if (status == DriveConnectionStatus.signedIn)
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(restorableDriveProjectsProvider),
            ),
        ],
      ),
      body: status != DriveConnectionStatus.signedIn
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Connect Google Drive Sync in Settings first, then come back here to '
                  'restore any projects found on Drive that aren\'t on this device yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : const _RestorableList(),
    );
  }
}

class _RestorableList extends ConsumerWidget {
  const _RestorableList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(restorableDriveProjectsProvider);

    return projectsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Could not check Drive: $error')),
      data: (projects) {
        if (projects.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No new projects found on Drive — everything on Drive is already on '
                'this device.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(restorableDriveProjectsProvider.future),
          child: ListView.builder(
            itemCount: projects.length,
            itemBuilder: (context, index) => _RestoreRow(project: projects[index]),
          ),
        );
      },
    );
  }
}

class _RestoreRow extends ConsumerStatefulWidget {
  const _RestoreRow({required this.project});

  final RestorableDriveProject project;

  @override
  ConsumerState<_RestoreRow> createState() => _RestoreRowState();
}

class _RestoreRowState extends ConsumerState<_RestoreRow> {
  bool _restoring = false;

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    // Only worth showing the raw folder name as a subtitle when it differs
    // from the title — i.e. the project was renamed after its first sync
    // (see drive_restore_service.dart's doc comment). Identical for anything
    // never renamed, so showing it there would just be noise.
    final showFolderName = project.folderName != project.title;

    return ListTile(
      leading: const Icon(Icons.menu_book_outlined),
      title: Text(project.title),
      subtitle: showFolderName
          ? Text(
              'Originally created as "${project.folderName}"',
              style: Theme.of(context).textTheme.bodySmall,
            )
          : null,
      trailing: _restoring
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : FilledButton.tonal(
              onPressed: _restore,
              child: const Text('Restore'),
            ),
    );
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    try {
      final library = ref.read(libraryServiceProvider);
      final syncService = await ref.read(driveSyncServiceProvider.future);
      final project = await restoreProjectFromDrive(
        folderName: widget.project.folderName,
        library: library,
        syncService: syncService,
      );
      // The book might belong to a series this device has never seen —
      // without this it'd open as a dangling "standalone" project, missing
      // whatever shared characters/world/notes/to-dos it actually belongs
      // to. No-ops if it's standalone or the series is already known.
      await restoreSeriesIfMissing(project: project, library: library, syncService: syncService);
      ref.invalidate(projectListProvider);
      ref.invalidate(seriesListProvider);
      ref.invalidate(restorableDriveProjectsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${project.title}" restored to your library')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _restoring = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Restore failed: $error')));
      }
    }
  }
}
