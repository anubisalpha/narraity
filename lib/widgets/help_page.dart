import 'package:flutter/material.dart';

import '../data/help_content.dart';
import '../models/help_topic.dart';

/// The Help page: every [HelpTopic] as its own collapsible segment, in a
/// single scrollable list. Deliberately segmented (rather than one long
/// page of text) for two reasons: it's easier to scan when most segments
/// stay collapsed, and each segment is the unit a future in-context help
/// icon on that screen will jump straight to via [initialTopicId] — see
/// `openHelpTopic` below.
class HelpPageContent extends StatefulWidget {
  const HelpPageContent({super.key, this.initialTopicId});

  /// If set, that topic starts expanded and scrolled into view — how a
  /// future per-screen help icon will land here instead of at the top of
  /// the list. Ignored if no topic with this id exists.
  final String? initialTopicId;

  @override
  State<HelpPageContent> createState() => _HelpPageContentState();
}

class _HelpPageContentState extends State<HelpPageContent> {
  final _searchController = TextEditingController();
  String _query = '';
  final _topicKeys = {for (final topic in helpTopics) topic.id: GlobalKey()};
  late final Set<String> _expanded = widget.initialTopicId != null
      ? {widget.initialTopicId!}
      : {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    if (widget.initialTopicId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToInitial());
    }
  }

  void _scrollToInitial() {
    final key = _topicKeys[widget.initialTopicId];
    final context = key?.currentContext;
    if (context == null || !mounted) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 300),
      alignment: 0.05,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// A topic matches [_query] if its title, intro, or any entry's title
  /// matches — searching by feature name ("dictation", "vault") is the
  /// common case, not searching by full description text.
  bool _matches(HelpTopic topic) {
    if (_query.isEmpty) return true;
    if (topic.title.toLowerCase().contains(_query)) return true;
    if (topic.intro?.toLowerCase().contains(_query) ?? false) return true;
    return topic.entries.any(
      (entry) =>
          entry.title.toLowerCase().contains(_query) ||
          entry.description.toLowerCase().contains(_query),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = helpTopics.where(_matches).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Help', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'What every icon and panel does, area by area.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search help…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _searchController.clear,
                  ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('No help topics match "$_query".'),
          )
        else
          for (final topic in visible) _HelpTopicCard(
            key: _topicKeys[topic.id],
            topic: topic,
            initiallyExpanded: _expanded.contains(topic.id),
            forceExpanded: _query.isNotEmpty,
          ),
      ],
    );
  }
}

class _HelpTopicCard extends StatelessWidget {
  const _HelpTopicCard({
    super.key,
    required this.topic,
    required this.initiallyExpanded,
    required this.forceExpanded,
  });

  final HelpTopic topic;
  final bool initiallyExpanded;

  /// While searching, every matching topic stays open so results don't
  /// need a second click to actually read.
  final bool forceExpanded;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey('${topic.id}-$forceExpanded'),
        initiallyExpanded: initiallyExpanded || forceExpanded,
        leading: Icon(topic.icon),
        title: Text(
          topic.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (topic.intro != null) ...[
            Text(topic.intro!, style: Theme.of(context).textTheme.bodyMedium),
            if (topic.entries.isNotEmpty) const SizedBox(height: 12),
          ],
          for (final entry in topic.entries) HelpEntryRow(entry: entry),
        ],
      ),
    );
  }
}

class HelpEntryRow extends StatelessWidget {
  const HelpEntryRow({super.key, required this.entry});

  final HelpEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(entry.icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
