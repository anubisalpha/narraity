import 'package:flutter/material.dart';

import '../data/help_content.dart';
import '../models/help_topic.dart';
import '../screens/settings_screen.dart' show openHelpTopic;
import 'help_page.dart';

/// The contextual help icon every page's top-right corner gets: opens
/// [showHelpPanel] for that page's own topic, so "what does this page do"
/// is always one click away instead of a trip through Settings.
class HelpIconButton extends StatelessWidget {
  const HelpIconButton({super.key, required this.topicId});

  /// Which [HelpTopic.id] this page's help icon opens — see
  /// `help_content.dart` for the full list.
  final String topicId;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Help',
      icon: const Icon(Icons.help_outline),
      onPressed: () => showHelpPanel(context, topicId),
    );
  }
}

/// Opens [topicId]'s segment as a panel sliding in from the right edge —
/// the same slide-from-the-right feel as the docked Reference Panel, but as
/// a dismissible overlay rather than a permanent layout slot, since most
/// pages that need a help icon (Timeline, Plot Grid, the Relationship
/// Diagram, …) don't have a spare docked panel to put it in.
///
/// Silently does nothing if [topicId] doesn't match a topic — a typo here
/// should never crash the page it's called from.
Future<void> showHelpPanel(BuildContext context, String topicId) {
  final topic = findHelpTopic(topicId);
  if (topic == null) return Future.value();

  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) =>
          _HelpPanel(topic: topic),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
    ),
  );
}

class _HelpPanel extends StatelessWidget {
  const _HelpPanel({required this.topic});

  final HelpTopic topic;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.of(context).size.width * 0.9).clamp(0.0, 380.0);

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surface,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
                  child: Row(
                    children: [
                      Icon(topic.icon),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          topic.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (topic.intro != null) ...[
                          Text(
                            topic.intro!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (topic.entries.isNotEmpty) const SizedBox(height: 16),
                        ],
                        for (final entry in topic.entries)
                          HelpEntryRow(entry: entry),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.menu_book_outlined, size: 18),
                      label: const Text('See full Help page'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        openHelpTopic(context, topic.id);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
