import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/contact.dart';
import '../models/notification_item.dart';
import '../models/project.dart';
import '../services/planning_scan.dart';
import 'contact_provider.dart';
import 'library_provider.dart';

/// Every pending planning/reviewer notification across the whole library,
/// most urgent first (overdue before due-soon, earliest due date first).
final notificationsProvider = FutureProvider<List<NotificationItem>>((ref) async {
  final library = ref.watch(libraryServiceProvider);
  final projects = await ref.watch(projectListProvider.future);
  final contacts = await ref.watch(contactListProvider.future);
  final contactsById = {for (final c in contacts) c.id: c};

  final snapshots = await Future.wait(
    projects.map((project) => scanProjectPlanning(library, project)),
  );

  final items = <NotificationItem>[];
  for (final snapshot in snapshots) {
    for (final milestone in snapshot.overdueMilestones) {
      items.add(NotificationItem(
        project: snapshot.project,
        kind: NotificationKind.milestoneOverdue,
        title: milestone.title,
        dueDate: milestone.dueDate,
      ));
    }
    for (final milestone in snapshot.dueSoonMilestones) {
      items.add(NotificationItem(
        project: snapshot.project,
        kind: NotificationKind.milestoneDueSoon,
        title: milestone.title,
        dueDate: milestone.dueDate,
      ));
    }
    for (final send in snapshot.overdueReviewerSends) {
      final Contact? contact = contactsById[send.contactId];
      items.add(NotificationItem(
        project: snapshot.project,
        kind: NotificationKind.reviewerOverdue,
        title: '${contact?.name ?? 'Unknown reviewer'} — copy overdue',
        dueDate: send.targetDeadline,
      ));
    }
  }

  items.sort((a, b) {
    final urgencyOrder = {
      NotificationKind.milestoneOverdue: 0,
      NotificationKind.reviewerOverdue: 0,
      NotificationKind.milestoneDueSoon: 1,
    };
    final urgencyCompare = urgencyOrder[a.kind]!.compareTo(urgencyOrder[b.kind]!);
    if (urgencyCompare != 0) return urgencyCompare;
    if (a.dueDate == null) return 1;
    if (b.dueDate == null) return -1;
    return a.dueDate!.compareTo(b.dueDate!);
  });

  return items;
});

/// [notificationsProvider] filtered to a single project, for the in-project
/// bell.
final notificationsForProjectProvider =
    FutureProvider.family<List<NotificationItem>, Project>((ref, project) async {
  final all = await ref.watch(notificationsProvider.future);
  return all.where((item) => item.project.id == project.id).toList();
});
