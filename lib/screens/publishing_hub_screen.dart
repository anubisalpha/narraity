import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/publishing_guidance.dart';
import '../models/contact.dart';
import '../models/project.dart';
import '../models/reviewer_send.dart';
import '../state/contact_provider.dart';
import '../state/manuscript_provider.dart';
import '../state/notifications_provider.dart';
import '../state/publishing_checklist_provider.dart';
import '../state/publishing_dashboard_provider.dart';
import '../state/reviewer_tracker_provider.dart';

/// Two-tab publishing surface: route-by-route guidance with a checklist,
/// paired web-search shortcuts and copyable AI-prompt templates (Guidance
/// tab), and the author's log of who has a manuscript copy out for review
/// (Reviewer Tracker tab). Content is transcribed from `Publishing Guidance
/// for Writers' Software.md`.
class PublishingHubScreen extends ConsumerStatefulWidget {
  const PublishingHubScreen({super.key, required this.project, this.initialTabIndex = 0});

  final Project project;
  final int initialTabIndex;

  @override
  ConsumerState<PublishingHubScreen> createState() => _PublishingHubScreenState();
}

class _PublishingHubScreenState extends ConsumerState<PublishingHubScreen>
    with SingleTickerProviderStateMixin {
  late final _tabController = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialTabIndex,
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Publishing Hub'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Guidance'),
            Tab(text: 'Reviewer Tracker'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _GuidanceTab(project: widget.project),
          _ReviewerTrackerTab(project: widget.project),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Guidance tab
// ---------------------------------------------------------------------------

class _GuidanceTab extends ConsumerWidget {
  const _GuidanceTab({required this.project});

  final Project project;

  Future<String> _wordCount(WidgetRef ref) async {
    final service = await ref.read(manuscriptServiceProvider(project).future);
    final structure = await ref.read(manuscriptStructureProvider(project).future);
    return service.totalWordCount(structure).toString();
  }

  String _fill(String template, {required String genre, required String wordCount}) {
    return template
        .replaceAll('{title}', project.title)
        .replaceAll('{author}', project.author?.isNotEmpty == true ? project.author! : 'me')
        .replaceAll('{genre}', genre.isEmpty ? '[your genre]' : genre)
        .replaceAll('{wordCount}', wordCount);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(publishingChecklistStateProvider(project));

    return stateAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Failed to load: $err')),
      data: (state) {
        final selectedRoute = state.selectedRoute;
        final items = publishingChecklistItems.where(
          (item) =>
              item.appliesToRoutes.isEmpty ||
              (selectedRoute != null && item.appliesToRoutes.contains(selectedRoute)),
        );
        final byStage = <String, List<ChecklistStageItem>>{};
        for (final item in items) {
          byStage.putIfAbsent(item.stage, () => []).add(item);
        }

        Future<void> persist(void Function() mutate) async {
          mutate();
          final service =
              await ref.read(publishingChecklistServiceProvider(project).future);
          await service.save(state);
          ref.invalidate(publishingChecklistStateProvider(project));
          ref.invalidate(publishingDashboardProvider);
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          children: [
            Text('Which route are you pursuing?',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<PublishingRoute?>(
              initialValue: selectedRoute,
              decoration: const InputDecoration(labelText: 'Publishing route'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Not decided yet')),
                for (final route in PublishingRoute.values)
                  DropdownMenuItem(
                    value: route,
                    child: Text(publishingRouteInfo[route]!.label),
                  ),
              ],
              onChanged: (route) => persist(() => state.selectedRoute = route),
            ),
            if (selectedRoute != null) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(publishingRouteInfo[selectedRoute]!.pitch),
                      const SizedBox(height: 4),
                      Text(
                        publishingRouteInfo[selectedRoute]!.metrics,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              initialValue: state.genre,
              decoration: const InputDecoration(
                labelText: 'Genre (fills search/AI prompt placeholders)',
              ),
              onChanged: (value) => persist(() => state.genre = value),
            ),
            const SizedBox(height: 24),
            for (final stage in byStage.keys) ...[
              Text(stage, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              for (final item in byStage[stage]!)
                _ChecklistTile(
                  item: item,
                  checked: state.checkedItemIds.contains(item.id),
                  onChanged: (checked) => persist(() {
                    if (checked) {
                      state.checkedItemIds.add(item.id);
                    } else {
                      state.checkedItemIds.remove(item.id);
                    }
                  }),
                  onSearch: item.whySearchQuery == null
                      ? null
                      : () async {
                          final query = _fill(item.whySearchQuery!,
                              genre: state.genre, wordCount: '');
                          await launchUrl(Uri.parse(
                              'https://www.google.com/search?q=${Uri.encodeQueryComponent(query)}'));
                        },
                  onCopyPrompt: item.aiPromptTemplate == null
                      ? null
                      : () async {
                          final wordCount = await _wordCount(ref);
                          final prompt = _fill(item.aiPromptTemplate!,
                              genre: state.genre, wordCount: wordCount);
                          await Clipboard.setData(ClipboardData(text: prompt));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('AI prompt copied to clipboard')),
                            );
                          }
                        },
                ),
              const SizedBox(height: 16),
            ],
            Text('Red Flags to Watch For', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final guardrail in publishingGuardrails)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_outlined,
                                size: 18,
                                color: Theme.of(context).colorScheme.onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                guardrail,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ChecklistTile extends StatelessWidget {
  const _ChecklistTile({
    required this.item,
    required this.checked,
    required this.onChanged,
    this.onSearch,
    this.onCopyPrompt,
  });

  final ChecklistStageItem item;
  final bool checked;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onSearch;
  final VoidCallback? onCopyPrompt;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: CheckboxListTile(
        value: checked,
        onChanged: (value) => onChanged(value ?? false),
        title: Text(item.title),
        controlAffinity: ListTileControlAffinity.leading,
        secondary: onSearch == null && onCopyPrompt == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onSearch != null)
                    IconButton(
                      tooltip: 'Search the web',
                      icon: const Icon(Icons.search),
                      onPressed: onSearch,
                    ),
                  if (onCopyPrompt != null)
                    IconButton(
                      tooltip: 'Copy AI prompt',
                      icon: const Icon(Icons.smart_toy_outlined),
                      onPressed: onCopyPrompt,
                    ),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reviewer Tracker tab
// ---------------------------------------------------------------------------

class _ReviewerTrackerTab extends ConsumerWidget {
  const _ReviewerTrackerTab({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sendsAsync = ref.watch(reviewerSendListProvider(project));
    final avgAsync = ref.watch(reviewerAverageTurnaroundProvider(project));
    final contactsAsync = ref.watch(contactListProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showEditReviewerSendDialog(context, ref, project: project),
        icon: const Icon(Icons.add),
        label: const Text('Log a Send'),
      ),
      body: sendsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Failed to load: $err')),
        data: (sends) {
          final contactsById = {
            for (final c in contactsAsync.valueOrNull ?? const <Contact>[]) c.id: c,
          };

          if (sends.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No copies sent out yet. Log one to start tracking turnaround.'),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            children: [
              avgAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (err, stack) => const SizedBox.shrink(),
                data: (avg) => avg == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Average turnaround: ${avg.toStringAsFixed(1)} days',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
              ),
              for (final send in sends)
                _ReviewerSendCard(
                  send: send,
                  contact: contactsById[send.contactId],
                  project: project,
                ),
            ],
          );
        },
      ),
    );
  }
}

String _statusLabel(ReviewerSendStatus status) => switch (status) {
  ReviewerSendStatus.inProgress => 'In Progress',
  ReviewerSendStatus.returned => 'Returned',
  ReviewerSendStatus.overdue => 'Overdue',
  ReviewerSendStatus.declined => 'Declined',
};

Color _statusColor(BuildContext context, ReviewerSendStatus status) => switch (status) {
  ReviewerSendStatus.inProgress => Theme.of(context).colorScheme.primary,
  ReviewerSendStatus.returned => Colors.green.shade700,
  ReviewerSendStatus.overdue => Theme.of(context).colorScheme.error,
  ReviewerSendStatus.declined => Theme.of(context).colorScheme.outline,
};

class _ReviewerSendCard extends ConsumerWidget {
  const _ReviewerSendCard({required this.send, required this.contact, required this.project});

  final ReviewerSend send;
  final Contact? contact;
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = send.statusAsOf(DateTime.now());
    final subtitleParts = <String>[
      'Sent ${DateFormat.yMMMd().format(send.dateSent)}',
      if (send.format.isNotEmpty) send.format,
      if (send.targetDeadline != null)
        'Due ${DateFormat.yMMMd().format(send.targetDeadline!)}',
      if (send.turnaroundDays != null) 'Took ${send.turnaroundDays} day(s)',
    ];

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _statusColor(context, status),
          child: Text(
            _statusLabel(status).substring(0, 1),
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Text(contact?.name ?? 'Unknown reviewer'),
        subtitle: Text(subtitleParts.join(' · ')),
        trailing: Chip(label: Text(_statusLabel(status))),
        onTap: () => showEditReviewerSendDialog(
          context,
          ref,
          project: project,
          send: send,
        ),
      ),
    );
  }
}

Future<void> showEditReviewerSendDialog(
  BuildContext context,
  WidgetRef ref, {
  required Project project,
  ReviewerSend? send,
}) {
  return showDialog(
    context: context,
    builder: (_) => _ReviewerSendDialog(project: project, send: send),
  );
}

class _ReviewerSendDialog extends ConsumerStatefulWidget {
  const _ReviewerSendDialog({required this.project, this.send});

  final Project project;
  final ReviewerSend? send;

  @override
  ConsumerState<_ReviewerSendDialog> createState() => _ReviewerSendDialogState();
}

class _ReviewerSendDialogState extends ConsumerState<_ReviewerSendDialog> {
  late final _formatController = TextEditingController(text: widget.send?.format ?? '');
  late final _notesController =
      TextEditingController(text: widget.send?.feedbackNotes ?? '');
  String? _contactId;
  late DateTime _dateSent = widget.send?.dateSent ?? DateTime.now();
  late DateTime? _targetDeadline = widget.send?.targetDeadline;
  late DateTime? _dateReturned = widget.send?.dateReturned;
  late bool _declined = widget.send?.declined ?? false;
  late int? _rating = widget.send?.rating;

  @override
  void initState() {
    super.initState();
    _contactId = widget.send?.contactId;
  }

  @override
  void dispose() {
    _formatController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? initial) => showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );

  Future<void> _save() async {
    final contactId = _contactId;
    if (contactId == null) return;

    final service = await ref.read(reviewerTrackerServiceProvider(widget.project).future);
    final existing = widget.send;
    if (existing == null) {
      await service.addSend(
        contactId: contactId,
        format: _formatController.text.trim(),
        dateSent: _dateSent,
        targetDeadline: _targetDeadline,
      );
    } else {
      await service.updateSend(
        existing.copyWith(
          contactId: contactId,
          format: _formatController.text.trim(),
          dateSent: _dateSent,
          targetDeadline: _targetDeadline,
          clearTargetDeadline: _targetDeadline == null,
          dateReturned: _dateReturned,
          clearDateReturned: _dateReturned == null,
          declined: _declined,
          rating: _rating,
          clearRating: _rating == null,
          feedbackNotes: _notesController.text.trim(),
        ),
      );
    }
    ref.invalidate(reviewerSendListProvider(widget.project));
    ref.invalidate(reviewerAverageTurnaroundProvider(widget.project));
    ref.invalidate(notificationsProvider);
    ref.invalidate(publishingDashboardProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactListProvider);

    return AlertDialog(
      title: Text(widget.send == null ? 'Log a Send' : 'Edit Send'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            contactsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (err, stack) => const SizedBox.shrink(),
              data: (contacts) {
                final eligible = contacts
                    .where((c) => [
                          ContactRole.betaReader,
                          ContactRole.arcReviewer,
                          ContactRole.editor,
                        ].contains(c.role))
                    .toList();
                return DropdownButtonFormField<String>(
                  initialValue: _contactId,
                  decoration: const InputDecoration(labelText: 'Reviewer'),
                  items: [
                    for (final contact in eligible)
                      DropdownMenuItem(value: contact.id, child: Text(contact.name)),
                  ],
                  onChanged: (id) => setState(() => _contactId = id),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _formatController,
              decoration: const InputDecoration(labelText: 'Format (EPUB, PDF, ...)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text('Sent: ${DateFormat.yMMMd().format(_dateSent)}')),
                TextButton(
                  onPressed: () async {
                    final picked = await _pick(_dateSent);
                    if (picked != null) setState(() => _dateSent = picked);
                  },
                  child: const Text('Change'),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(_targetDeadline == null
                      ? 'No deadline set'
                      : 'Deadline: ${DateFormat.yMMMd().format(_targetDeadline!)}'),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await _pick(_targetDeadline);
                    if (picked != null) setState(() => _targetDeadline = picked);
                  },
                  child: const Text('Set'),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(_dateReturned == null
                      ? 'Not returned yet'
                      : 'Returned: ${DateFormat.yMMMd().format(_dateReturned!)}'),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await _pick(_dateReturned);
                    if (picked != null) setState(() => _dateReturned = picked);
                  },
                  child: const Text('Mark returned'),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Declined / ghosted'),
              value: _declined,
              onChanged: (value) => setState(() => _declined = value),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              initialValue: _rating,
              decoration: const InputDecoration(labelText: 'Rating (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('No rating')),
                for (var i = 1; i <= 5; i++)
                  DropdownMenuItem(value: i, child: Text('$i / 5')),
              ],
              onChanged: (value) => setState(() => _rating = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Feedback notes (optional)'),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _contactId == null ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
