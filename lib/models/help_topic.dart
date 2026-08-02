import 'package:flutter/material.dart';

/// One explainable feature or icon within a [HelpTopic] — the smallest unit
/// the Help page renders. Deliberately just icon + title + description: no
/// markup, no navigation, so writing an entry never turns into a layout
/// task, and the same data can drive a future in-context tooltip as easily
/// as a full page.
class HelpEntry {
  const HelpEntry({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

/// One self-contained area of the app (a screen, a toolbar, a panel) shown
/// as its own segment on the Help page.
///
/// [id] is a stable key — unrelated to display order or [title], which can
/// both change freely — so a future in-context help icon on, say, the
/// project shell can jump straight to the `projectToolbar` segment instead
/// of dumping the reader at the top of a long page (see
/// `openHelpTopic` in `help_screen_content.dart`). Once a segment ships,
/// keep its id: renaming it silently breaks whatever deep-link already
/// points at it.
class HelpTopic {
  const HelpTopic({
    required this.id,
    required this.title,
    required this.icon,
    this.intro,
    this.entries = const [],
  });

  final String id;
  final String title;
  final IconData icon;

  /// A sentence or two of orientation before the entry list — what this
  /// area is *for*, not a repeat of the entries below it. Some topics
  /// (mostly settings pointers) have no entries and are just this.
  final String? intro;

  final List<HelpEntry> entries;
}
