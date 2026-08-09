import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/project.dart';
import 'drive_remote_store.dart';
import 'drive_sync_service.dart';
import 'library_service.dart';

/// One Drive-only project folder available to restore. [folderName] is the
/// stable, never-renamed identifier `DriveSyncService`/`DriveRemoteStore`
/// need to actually pull it down; [title] is what to *show* the user — see
/// [findRestorableProjects]'s doc comment for why those two are often
/// different strings for the same project.
class RestorableDriveProject {
  const RestorableDriveProject({required this.folderName, required this.title});

  final String folderName;
  final String title;
}

/// Finds project folders that exist on Drive but not on this device.
///
/// Sync itself (`DriveSyncService.sync`/`runFullSyncAcrossAllTargets`) never
/// discovers these — it only ever round-trips projects the library already
/// knows about locally (`LibraryService.listProjects()`), by design: a
/// single project's sync is a diff of *that project's own* local vs. remote
/// files, and nothing ever asks "what else is under Narraity/ that I don't
/// have a local folder for at all." A fresh install or a new device
/// therefore signs in, syncs successfully, and still shows an empty
/// library — sync keeps existing projects in sync, it doesn't restore ones
/// this device has never seen. This is the missing other half.
///
/// Each candidate's `project.json` is fetched and its **title** shown, not
/// the raw Drive folder name — `LibraryService.renameProject` deliberately
/// never renames the on-disk (and therefore Drive) folder, only the title
/// inside `project.json` (see that method's own doc comment for why: folder
/// renames risk collisions and stale stored paths). A project renamed after
/// its first sync therefore keeps its *original* creation-time name as its
/// Drive folder name forever. Showing that raw folder name here looked like
/// a stray duplicate "artifact" left over from the old name — it wasn't a
/// duplicate, just this screen surfacing an internal identifier instead of
/// the name the user actually gave the project. Falls back to the folder
/// name only if `project.json` is missing/corrupt on the remote side.
Future<List<RestorableDriveProject>> findRestorableProjects({
  required DriveRemoteStore remote,
  required LibraryService library,
}) async {
  final remoteNames = await remote.listProjectFolderNames();
  final localNames = (await library.listProjects()).map((project) => project.folderName).toSet();
  final restorableNames = remoteNames.where((name) => !localNames.contains(name)).toList()
    ..sort();

  final results = <RestorableDriveProject>[];
  for (final folderName in restorableNames) {
    results.add(
      RestorableDriveProject(folderName: folderName, title: await _peekTitle(remote, folderName)),
    );
  }
  return results;
}

Future<String> _peekTitle(DriveRemoteStore remote, String folderName) async {
  try {
    final file = await remote.findFile(projectFolderName: folderName, relativePath: 'project.json');
    if (file == null) return folderName;
    final bytes = await remote.download(file.id);
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final title = json['title'] as String?;
    return (title == null || title.isEmpty) ? folderName : title;
  } catch (_) {
    // Unreadable/corrupt project.json on the remote side — fall back to the
    // folder name rather than failing the whole restorable-projects list
    // over one bad entry.
    return folderName;
  }
}

/// Pulls one Drive-only project folder down as a brand-new local project.
///
/// Deliberately does *not* go through `LibraryService.createProject` — that
/// generates its own uuid and a fresh, possibly-renamed folder name (via
/// its collision-avoidance), which would create an empty folder alongside
/// the real one on Drive instead of mirroring it. [folderName] must be the
/// exact Drive folder name from [findRestorableProjectNames], so
/// `DriveSyncService.sync` looks at the right remote folder and treats
/// every file in it as new-to-download.
Future<Project> restoreProjectFromDrive({
  required String folderName,
  required LibraryService library,
  required DriveSyncService syncService,
}) async {
  final root = await library.libraryRoot();
  final projectDir = Directory(p.join(root.path, folderName));
  await projectDir.create(recursive: true);

  await syncService.sync(projectDir, folderName);

  final projectFile = File(p.join(projectDir.path, 'project.json'));
  if (!await projectFile.exists()) {
    // Nothing usable came down (an empty/corrupt remote folder) — don't
    // leave a phantom empty folder behind for listProjects to trip over.
    await projectDir.delete(recursive: true);
    throw StateError('"$folderName" on Drive has no project.json — nothing to restore.');
  }

  final json = jsonDecode(await projectFile.readAsString()) as Map<String, dynamic>;
  return Project.fromJson(json, folderName: folderName);
}
