import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../state/notifications_provider.dart';

/// A persistent bell icon with a count badge — used on both the library
/// screen (library-wide notifications) and inside a project (that project's
/// notifications only). Opens the host `Scaffold`'s end drawer, which the
/// caller is responsible for supplying (`NotificationsSidebar`).
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key, this.project});

  /// When set, shows only this project's notifications. Null shows every
  /// project's (library screen).
  final Project? project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = project == null
        ? ref.watch(notificationsProvider)
        : ref.watch(notificationsForProjectProvider(project!));
    final count = itemsAsync.valueOrNull?.length ?? 0;

    return IconButton(
      tooltip: count == 0 ? 'Notifications' : '$count pending notification(s)',
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () => Scaffold.of(context).openEndDrawer(),
    );
  }
}
