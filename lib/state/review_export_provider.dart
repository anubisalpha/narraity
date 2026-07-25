import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../services/review_export_service.dart';
import 'annotation_provider.dart';
import 'manuscript_provider.dart';

final reviewExportServiceProvider =
    FutureProvider.family<ReviewExportService, Project>((ref, project) async {
  final manuscriptService = await ref.watch(manuscriptServiceProvider(project).future);
  final annotationService = await ref.watch(annotationServiceProvider(project).future);
  return ReviewExportService(manuscriptService, annotationService);
});
