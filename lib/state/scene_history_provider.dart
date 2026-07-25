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
  // are signed without needing an app restart.
  ref.watch(vaultStatusProvider);
  final keyManager = await ref.watch(historySigningKeyManagerProvider.future);
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
