import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/project.dart';
import '../models/timeline.dart';
import '../services/timeline_service.dart';
import 'library_provider.dart';

final timelineServiceProvider =
    FutureProvider.family<TimelineService, Project>((ref, project) async {
  final root = await ref.watch(libraryServiceProvider).libraryRoot();
  return TimelineService(Directory(p.join(root.path, project.folderName)));
});

final timelineTrackListProvider =
    FutureProvider.family<List<TimelineTrack>, Project>((ref, project) async {
  final service = await ref.watch(timelineServiceProvider(project).future);
  return service.listTracks();
});

final timelineEventListProvider =
    FutureProvider.family<List<TimelineEvent>, Project>((ref, project) async {
  final service = await ref.watch(timelineServiceProvider(project).future);
  return service.listEvents();
});

/// Which track ids are currently hidden — toggleable/overlayable view per
/// PLAN.md. Not persisted: a fresh project open shows every track, which is
/// the safer default (a hidden track can't be mistaken for "doesn't exist").
final hiddenTrackIdsProvider = StateProvider<Set<String>>((ref) => {});

void invalidateTimeline(WidgetRef ref, Project project) {
  ref.invalidate(timelineTrackListProvider(project));
  ref.invalidate(timelineEventListProvider(project));
}
