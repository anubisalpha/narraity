import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/project.dart';
import '../models/publishing_checklist_state.dart';
import '../services/publishing_checklist_service.dart';
import 'library_provider.dart';

final publishingChecklistServiceProvider =
    FutureProvider.family<PublishingChecklistService, Project>((ref, project) async {
  final root = await ref.watch(libraryServiceProvider).libraryRoot();
  return PublishingChecklistService(Directory(p.join(root.path, project.folderName)));
});

final publishingChecklistStateProvider =
    FutureProvider.family<PublishingChecklistState, Project>((ref, project) async {
  final service = await ref.watch(publishingChecklistServiceProvider(project).future);
  return service.load();
});
