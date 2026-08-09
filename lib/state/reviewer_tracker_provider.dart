import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/project.dart';
import '../models/reviewer_send.dart';
import '../services/reviewer_tracker_service.dart';
import 'library_provider.dart';

final reviewerTrackerServiceProvider =
    FutureProvider.family<ReviewerTrackerService, Project>((ref, project) async {
  final root = await ref.watch(libraryServiceProvider).libraryRoot();
  return ReviewerTrackerService(Directory(p.join(root.path, project.folderName)));
});

final reviewerSendListProvider =
    FutureProvider.family<List<ReviewerSend>, Project>((ref, project) async {
  final service = await ref.watch(reviewerTrackerServiceProvider(project).future);
  return service.listSends();
});

/// Average turnaround (days) across this project's returned sends, or null
/// if none have returned yet.
final reviewerAverageTurnaroundProvider =
    FutureProvider.family<double?, Project>((ref, project) async {
  final sends = await ref.watch(reviewerSendListProvider(project).future);
  final turnarounds = sends.map((s) => s.turnaroundDays).whereType<int>().toList();
  if (turnarounds.isEmpty) return null;
  return turnarounds.reduce((a, b) => a + b) / turnarounds.length;
});
