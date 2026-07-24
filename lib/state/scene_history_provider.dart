import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../models/scene_snapshot.dart';
import '../services/scene_history_service.dart';
import 'manuscript_provider.dart';

final sceneHistoryServiceProvider =
    FutureProvider.family<SceneHistoryService, Project>((ref, project) async {
  final manuscriptService = await ref.watch(manuscriptServiceProvider(project).future);
  return SceneHistoryService(manuscriptService.projectDir);
});

/// Snapshots for one scene, family-keyed by (project, sceneId).
final sceneSnapshotsProvider = FutureProvider.family<List<SceneSnapshot>, (Project, String)>(
  (ref, args) async {
    final (project, sceneId) = args;
    final service = await ref.watch(sceneHistoryServiceProvider(project).future);
    return service.listSnapshots(sceneId);
  },
);
