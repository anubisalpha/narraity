import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/project.dart';
import '../models/relationship.dart';
import '../services/relationship_service.dart';
import 'library_provider.dart';

final relationshipServiceProvider =
    FutureProvider.family<RelationshipService, Project>((ref, project) async {
  final root = await ref.watch(libraryServiceProvider).libraryRoot();
  return RelationshipService(Directory(p.join(root.path, project.folderName)));
});

final relationshipListProvider =
    FutureProvider.family<List<Relationship>, Project>((ref, project) async {
  final service = await ref.watch(relationshipServiceProvider(project).future);
  return service.listRelationships();
});

final relationshipLayoutProvider =
    FutureProvider.family<Map<String, (double, double)>, Project>((ref, project) async {
  final service = await ref.watch(relationshipServiceProvider(project).future);
  return service.loadLayout();
});

void invalidateRelationships(WidgetRef ref, Project project) {
  ref.invalidate(relationshipListProvider(project));
  ref.invalidate(relationshipLayoutProvider(project));
}
