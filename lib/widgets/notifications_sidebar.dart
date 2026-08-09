import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/notification_item.dart';
import '../models/project.dart';
import '../screens/planning_screen.dart';
import '../screens/publishing_hub_screen.dart';
import '../state/notifications_provider.dart';

IconData _iconFor(NotificationKind kind) => switch (kind) {
  NotificationKind.milestoneOverdue => Icons.event_busy,
  NotificationKind.milestoneDueSoon => Icons.event_outlined,
  NotificationKind.reviewerOverdue => Icons.rate_review_outlined,
};

Color _colorFor(BuildContext context, NotificationKind kind) => switch (kind) {
  NotificationKind.milestoneOverdue => Theme.of(context).colorScheme.error,
  NotificationKind.reviewerOverdue => Theme.of(context).colorScheme.error,
  NotificationKind.milestoneDueSoon => Colors.amber.shade800,
};

/// End-drawer content listing pending [NotificationItem]s. Pass [project] to
/// scope to one project (in-project bell, flat list); omit for the
/// library-wide bell (grouped by project).
class NotificationsSidebar extends ConsumerWidget {
  const NotificationsSidebar({super.key, this.project});

  final Project? project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = project == null
        ? ref.watch(notificationsProvider)
        : ref.watch(notificationsForProjectProvider(project!));

    return Drawer(
      child: SafeArea(
        child: itemsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Failed to load: $err')),
          data: (items) {
            if (items.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nothing pending — you\'re all caught up.'),
                ),
              );
            }

            if (project != null) {
              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      'Notifications',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  for (final item in items) _NotificationTile(item: item),
                ],
              );
            }

            final byProject = <String, List<NotificationItem>>{};
            for (final item in items) {
              byProject.putIfAbsent(item.project.id, () => []).add(item);
            }

            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Notifications',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                for (final entry in byProject.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      entry.value.first.project.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  for (final item in entry.value) _NotificationTile(item: item),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});

  final NotificationItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_iconFor(item.kind), color: _colorFor(context, item.kind)),
      title: Text(item.title),
      subtitle: item.dueDate == null
          ? null
          : Text('Due ${DateFormat.yMMMd().format(item.dueDate!)}'),
      onTap: () {
        Navigator.of(context).pop(); // close the drawer
        final destination = item.kind == NotificationKind.reviewerOverdue
            ? PublishingHubScreen(project: item.project, initialTabIndex: 1)
            : PlanningScreen(project: item.project);
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => destination));
      },
    );
  }
}
