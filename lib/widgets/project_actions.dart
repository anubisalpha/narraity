import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../state/library_provider.dart';
import 'edit_style_dialog.dart';

/// Card-style edit, archive, and delete actions for a project — shared
/// between the library screen's own project cards and a series' member
/// cards (`series_detail_screen.dart`), since both need the exact same
/// confirmation dialogs, loading feedback, and provider invalidation, not
/// just visually similar but independently-maintained copies.
///
/// Shows a non-dismissible "working" dialog while an archive/delete future
/// runs, then closes it — archiving/deleting zips the whole project folder
/// and can occasionally take a while to finish removing the source folder
/// on Windows (see `LibraryService._deleteWithRetry`'s doc comment for why),
/// so a silent multi-second wait would otherwise look like the app hung.
Future<void> _runWithLoadingDialog(BuildContext context, String message, Future<void> future) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      content: Row(
        children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 16),
          Text(message),
        ],
      ),
    ),
  );
  try {
    await future;
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

Future<void> editProjectCardStyle(BuildContext context, WidgetRef ref, Project project) async {
  final newKind = await showEditStyleDialog(context, project.kind);
  if (newKind == null || newKind == project.kind) return;

  final libraryService = ref.read(libraryServiceProvider);
  await libraryService.saveProject(project.copyWith(kind: newKind, modified: DateTime.now()));
  ref.invalidate(projectListProvider);
}

Future<void> archiveProjectWithConfirmation(BuildContext context, WidgetRef ref, Project project) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Archive this project?'),
      content: Text(
        '"${project.title}" will be compressed and moved out of your library. You can restore '
        'it any time from Archived Projects.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Archive'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final libraryService = ref.read(libraryServiceProvider);
  await _runWithLoadingDialog(context, 'Archiving…', libraryService.archiveProject(project));
  ref.invalidate(projectListProvider);
}

Future<void> deleteProjectWithConfirmation(BuildContext context, WidgetRef ref, Project project) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete this project?'),
      content: Text(
        '"${project.title}" will be compressed and moved out of your library, the same as '
        'archiving. You can restore it any time from Deleted Projects — Narraity never '
        'permanently deletes anything on its own. If you want it gone for good, remove it '
        'from there via your file system.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final libraryService = ref.read(libraryServiceProvider);
  await _runWithLoadingDialog(context, 'Deleting…', libraryService.deleteProject(project));
  ref.invalidate(projectListProvider);
}
