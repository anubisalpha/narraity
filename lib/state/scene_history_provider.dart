import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../models/scene_snapshot.dart';
import '../services/scene_history_service.dart';
import 'manuscript_provider.dart';
import 'vault_provider.dart';

final sceneHistoryServiceProvider =
    FutureProvider.family<SceneHistoryService, Project>((ref, project) async {
  final manuscriptService = await ref.watch(manuscriptServiceProvider(project).future);
  // Watching the vault status (not just the manager) rebuilds this service
  // when the vault is unlocked mid-session, so snapshots taken after unlock
  // are signed without needing an app restart. The per-project password is
  // watched too so a project that uses its own vault password rebuilds on its
  // own unlock, not only the library-wide one.
  // Rebuild this service whenever a vault is unlocked/locked mid-session so
  // snapshots after unlock are signed without an app restart. Watching the
  // session-password StateProviders (which change on setup/unlock/lock/rekey)
  // rather than the async vaultStatusProvider avoids an await-cycle deadlock:
  // vaultStatusProvider and effectiveSigningKeyManagerProvider both await
  // historySigningKeyManagerProvider, and watching the former here while
  // awaiting the latter wedged the build when the library was unconfigured.
  ref.watch(vaultSessionPasswordProvider);
  ref.watch(projectVaultPasswordProvider(project.folderName));
  final keyManager = await ref.watch(effectiveSigningKeyManagerProvider(project).future);
  return SceneHistoryService(manuscriptService.projectDir, keyManager: keyManager);
});

/// Snapshots for one scene, family-keyed by (project, sceneId).
final sceneSnapshotsProvider = FutureProvider.family<List<SceneSnapshot>, (Project, String)>(
  (ref, args) async {
    final (project, sceneId) = args;
    final service = await ref.watch(sceneHistoryServiceProvider(project).future);
    return service.listSnapshots(sceneId);
  },
);
