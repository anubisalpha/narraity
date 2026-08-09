import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/planning_milestone.dart';
import '../models/project.dart';
import '../models/reviewer_send.dart';
import 'library_service.dart';
import 'planning_service.dart';
import 'reviewer_tracker_service.dart';

/// One project's planning/reviewer-tracker state as of "now" — the shared
/// read used by both the Notifications bell and the Publishing Dashboard so
/// neither duplicates the other's disk reads.
class ProjectPlanningSnapshot {
  ProjectPlanningSnapshot({
    required this.project,
    required this.overdueMilestones,
    required this.dueSoonMilestones,
    required this.overdueReviewerSends,
  });

  final Project project;
  final List<PlanningMilestone> overdueMilestones;
  final List<PlanningMilestone> dueSoonMilestones;
  final List<ReviewerSend> overdueReviewerSends;
}

/// Loads [project]'s milestones + reviewer sends and classifies them as of
/// [now] (defaults to `DateTime.now()` — overridable for tests).
Future<ProjectPlanningSnapshot> scanProjectPlanning(
  LibraryService library,
  Project project, {
  DateTime? now,
}) async {
  final effectiveNow = now ?? DateTime.now();
  final root = await library.libraryRoot();
  final projectDir = Directory(p.join(root.path, project.folderName));

  final milestones = await PlanningService(projectDir).listMilestones();
  final reviewerSends = await ReviewerTrackerService(projectDir).listSends();

  return ProjectPlanningSnapshot(
    project: project,
    overdueMilestones: milestones
        .where((m) => m.statusAsOf(effectiveNow) == PlanningMilestoneStatus.overdue)
        .toList(),
    dueSoonMilestones: milestones
        .where((m) => m.statusAsOf(effectiveNow) == PlanningMilestoneStatus.dueSoon)
        .toList(),
    overdueReviewerSends: reviewerSends
        .where((s) => s.statusAsOf(effectiveNow) == ReviewerSendStatus.overdue)
        .toList(),
  );
}
