import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/publishing_guidance.dart';
import '../state/publishing_dashboard_provider.dart';
import '../widgets/help_drawer.dart';
import 'planning_screen.dart';
import 'publishing_hub_screen.dart';

/// Library-root overview — one card per project showing its publishing
/// route, checklist progress, next deadline, and reviewer-tracker status at
/// a glance, so the author doesn't have to open every project to check.
class PublishingDashboardScreen extends ConsumerWidget {
  const PublishingDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summariesAsync = ref.watch(publishingDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Publishing Dashboard'),
        actions: const [
          HelpIconButton(topicId: 'publishingDashboard'),
          SizedBox(width: 8),
        ],
      ),
      body: summariesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Failed to load dashboard: $err')),
        data: (summaries) => summaries.isEmpty
            ? const _EmptyDashboard()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: summaries.length,
                itemBuilder: (context, index) => _ProjectSummaryCard(summary: summaries[index]),
              ),
      ),
    );
  }
}

class _EmptyDashboard extends StatelessWidget {
  const _EmptyDashboard();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.dashboard_outlined,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text('No projects yet', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Create a project to start planning its publishing timeline.'),
        ],
      ),
    );
  }
}

class _ProjectSummaryCard extends StatelessWidget {
  const _ProjectSummaryCard({required this.summary});

  final ProjectPlanningSummary summary;

  @override
  Widget build(BuildContext context) {
    final route = summary.checklistState.selectedRoute;
    final (checked, total) = summary.checklistProgress;
    final next = summary.nextMilestone;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    summary.project.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(
                    route == null ? 'No route chosen yet' : publishingRouteInfo[route]!.label,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (total > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: total == 0 ? 0 : checked / total),
              ),
              const SizedBox(height: 4),
              Text('$checked / $total checklist items', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
            ],
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PlanningScreen(project: summary.project)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.event_outlined,
                    size: 18,
                    color: summary.overdueMilestoneCount > 0
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      next == null
                          ? (summary.overdueMilestoneCount + summary.dueSoonCount == 0
                              ? 'No upcoming milestones'
                              : '${summary.overdueMilestoneCount} overdue, ${summary.dueSoonCount} due soon')
                          : 'Next: ${next.title} — ${DateFormat.yMMMd().format(next.dueDate!)}',
                      style: TextStyle(
                        color: summary.overdueMilestoneCount > 0
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PublishingHubScreen(project: summary.project, initialTabIndex: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.rate_review_outlined,
                    size: 18,
                    color: summary.reviewersOverdueCount > 0
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${summary.reviewersOutCount} out, ${summary.reviewersOverdueCount} overdue',
                    style: TextStyle(
                      color: summary.reviewersOverdueCount > 0
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
