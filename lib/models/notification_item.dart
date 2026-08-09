import '../models/project.dart';

/// A single pending item shown in the notification bell/sidebar. Not
/// persisted — built fresh from [ProjectPlanningSnapshot]s each time, so an
/// item simply disappears once its underlying milestone is marked done or
/// its reviewer send is updated. There's no "dismiss"/"read" state in v1.
enum NotificationKind { milestoneOverdue, milestoneDueSoon, reviewerOverdue }

class NotificationItem {
  NotificationItem({
    required this.project,
    required this.kind,
    required this.title,
    this.dueDate,
  });

  final Project project;
  final NotificationKind kind;
  final String title;
  final DateTime? dueDate;
}
