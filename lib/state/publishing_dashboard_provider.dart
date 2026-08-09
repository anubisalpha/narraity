import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/publishing_guidance.dart';
import '../models/planning_milestone.dart';
import '../models/project.dart';
import '../models/publishing_checklist_state.dart';
import '../services/planning_scan.dart';
import 'library_provider.dart';
import 'planning_provider.dart';
import 'publishing_checklist_provider.dart';
import 'reviewer_tracker_provider.dart';

/// One project's planning/publishing status, summarised for the Publishing
/// Dashboard. Plain computed data — not persisted.
class ProjectPlanningSummary {
  ProjectPlanningSummary({
    required this.project,
    required this.overdueMilestoneCount,
    required this.dueSoonCount,
    required this.nextMilestone,
    required this.checklistState,
    required this.checklistProgress,
    required this.reviewersOutCount,
    required this.reviewersOverdueCount,
  });

  final Project project;
  final int overdueMilestoneCount;
  final int dueSoonCount;
  final PlanningMilestone? nextMilestone;
  final PublishingChecklistState checklistState;

  /// (checked, applicable-total) for the checklist items that apply to this
  /// project's selected route (or Stage-1-only items if no route chosen).
  final (int checked, int total) checklistProgress;

  final int reviewersOutCount;
  final int reviewersOverdueCount;
}

List<String> _applicableChecklistItemIds(PublishingChecklistState state) {
  final route = state.selectedRoute;
  return [
    for (final item in publishingChecklistItems)
      if (item.appliesToRoutes.isEmpty || (route != null && item.appliesToRoutes.contains(route)))
        item.id,
  ];
}

/// One summary per project, in the same order as [projectListProvider].
final publishingDashboardProvider =
    FutureProvider<List<ProjectPlanningSummary>>((ref) async {
  final library = ref.watch(libraryServiceProvider);
  final projects = await ref.watch(projectListProvider.future);

  return Future.wait(projects.map((project) async {
    final snapshot = await scanProjectPlanning(library, project);

    final checklistService =
        await ref.watch(publishingChecklistServiceProvider(project).future);
    final checklistState = await checklistService.load();
    final applicableIds = _applicableChecklistItemIds(checklistState);

    final milestoneService = await ref.watch(planningServiceProvider(project).future);
    final milestones = await milestoneService.listMilestones();
    final upcoming = milestones.where((m) => !m.done && m.dueDate != null).toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

    final reviewerService = await ref.watch(reviewerTrackerServiceProvider(project).future);
    final reviewerSends = await reviewerService.listSends();

    return ProjectPlanningSummary(
      project: project,
      overdueMilestoneCount: snapshot.overdueMilestones.length,
      dueSoonCount: snapshot.dueSoonMilestones.length,
      nextMilestone: upcoming.isEmpty ? null : upcoming.first,
      checklistState: checklistState,
      checklistProgress: (
        applicableIds.where(checklistState.checkedItemIds.contains).length,
        applicableIds.length,
      ),
      reviewersOutCount:
          reviewerSends.where((s) => s.dateReturned == null && !s.declined).length,
      reviewersOverdueCount: snapshot.overdueReviewerSends.length,
    );
  }));
});
