import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/planning_milestone.dart';
import '../models/project.dart';
import '../services/planning_service.dart';
import 'library_provider.dart';

final planningServiceProvider =
    FutureProvider.family<PlanningService, Project>((ref, project) async {
  final root = await ref.watch(libraryServiceProvider).libraryRoot();
  return PlanningService(Directory(p.join(root.path, project.folderName)));
});

final planningListProvider =
    FutureProvider.family<List<PlanningMilestone>, Project>((ref, project) async {
  final service = await ref.watch(planningServiceProvider(project).future);
  return service.listMilestones();
});
