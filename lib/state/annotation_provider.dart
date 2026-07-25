import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/annotation.dart';
import '../models/project.dart';
import '../services/annotation_service.dart';
import 'manuscript_provider.dart';

final annotationServiceProvider =
    FutureProvider.family<AnnotationService, Project>((ref, project) async {
  final manuscriptService = await ref.watch(manuscriptServiceProvider(project).future);
  return AnnotationService(manuscriptService.projectDir);
});

/// Annotations for one scene, family-keyed by (project, sceneId) — same
/// convention as `sceneSnapshotsProvider`. Plain `listForScene`, no
/// resolution: the editor calls `resolveForScene` itself once it has the
/// live content, then invalidates this to pick up any self-healed offsets.
final sceneAnnotationsProvider = FutureProvider.family<List<Annotation>, (Project, String)>(
  (ref, args) async {
    final (project, sceneId) = args;
    final service = await ref.watch(annotationServiceProvider(project).future);
    return service.listForScene(sceneId);
  },
);

/// Refreshes a scene's annotation list after any write. Call after create/
/// update/delete rather than invalidating ad hoc at each call site.
void invalidateSceneAnnotations(WidgetRef ref, Project project, String sceneId) {
  ref.invalidate(sceneAnnotationsProvider((project, sceneId)));
}
