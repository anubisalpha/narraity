import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/goal.dart';
import '../models/project.dart';
import '../services/goals_service.dart';
import 'library_provider.dart';
import 'manuscript_provider.dart';

final goalsServiceProvider =
    FutureProvider.family<GoalsService, Project>((ref, project) async {
  final root = await ref.watch(libraryServiceProvider).libraryRoot();
  final manuscriptService = await ref.watch(manuscriptServiceProvider(project).future);
  return GoalsService(Directory(p.join(root.path, project.folderName)), manuscriptService);
});

final goalListProvider =
    FutureProvider.family<List<Goal>, Project>((ref, project) async {
  final service = await ref.watch(goalsServiceProvider(project).future);
  return service.listGoals();
});
