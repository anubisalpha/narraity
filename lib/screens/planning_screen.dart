import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/contact.dart';
import '../models/planning_milestone.dart';
import '../models/project.dart';
import '../state/contact_provider.dart';
import '../state/notifications_provider.dart';
import '../state/planning_provider.dart';
import '../state/publishing_dashboard_provider.dart';
import '../widgets/help_drawer.dart';

class PlanningScreen extends ConsumerWidget {
  const PlanningScreen({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final milestonesAsync = ref.watch(planningListProvider(project));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planning'),
        actions: const [HelpIconButton(topicId: 'planning'), SizedBox(width: 8)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showEditMilestoneDialog(context, ref, project: project),
        icon: const Icon(Icons.add),
        label: const Text('New Milestone'),
      ),
      body: milestonesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Failed to load planning: $err')),
        data: (milestones) {
          if (milestones.isEmpty) return const _EmptyPlanning();

          final now = DateTime.now();
          final grouped = <PlanningMilestoneStatus, List<PlanningMilestone>>{
            for (final status in PlanningMilestoneStatus.values) status: [],
          };
          for (final m in milestones) {
            grouped[m.statusAsOf(now)]!.add(m);
          }
          for (final list in grouped.values) {
            list.sort((a, b) {
              if (a.dueDate == null) return 1;
              if (b.dueDate == null) return -1;
              return a.dueDate!.compareTo(b.dueDate!);
            });
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            children: [
              for (final status in const [
                PlanningMilestoneStatus.overdue,
                PlanningMilestoneStatus.dueSoon,
                PlanningMilestoneStatus.upcoming,
                PlanningMilestoneStatus.done,
              ])
                if (grouped[status]!.isNotEmpty)
                  _StatusSection(
                    status: status,
                    milestones: grouped[status]!,
                    project: project,
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyPlanning extends StatelessWidget {
  const _EmptyPlanning();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_note_outlined,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text('No milestones yet', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Add publishing deadlines to keep the project on track.'),
        ],
      ),
    );
  }
}

String _statusLabel(PlanningMilestoneStatus status) => switch (status) {
  PlanningMilestoneStatus.overdue => 'Overdue',
  PlanningMilestoneStatus.dueSoon => 'Due Soon',
  PlanningMilestoneStatus.upcoming => 'Upcoming',
  PlanningMilestoneStatus.done => 'Done',
};

Color _statusColor(BuildContext context, PlanningMilestoneStatus status) =>
    switch (status) {
      PlanningMilestoneStatus.overdue => Theme.of(context).colorScheme.error,
      PlanningMilestoneStatus.dueSoon => Colors.amber.shade800,
      PlanningMilestoneStatus.upcoming => Theme.of(context).colorScheme.primary,
      PlanningMilestoneStatus.done => Theme.of(context).colorScheme.outline,
    };

class _StatusSection extends StatelessWidget {
  const _StatusSection({
    required this.status,
    required this.milestones,
    required this.project,
  });

  final PlanningMilestoneStatus status;
  final List<PlanningMilestone> milestones;
  final Project project;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              _statusLabel(status),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _statusColor(context, status),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          for (final milestone in milestones)
            _MilestoneCard(milestone: milestone, project: project),
        ],
      ),
    );
  }
}

class _MilestoneCard extends ConsumerWidget {
  const _MilestoneCard({required this.milestone, required this.project});

  final PlanningMilestone milestone;
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = milestone.statusAsOf(DateTime.now());
    return Card(
      child: ListTile(
        leading: Checkbox(
          value: milestone.done,
          onChanged: (done) async {
            final service = await ref.read(planningServiceProvider(project).future);
            await service.updateMilestone(milestone.copyWith(done: done ?? false));
            ref.invalidate(planningListProvider(project));
            ref.invalidate(notificationsProvider);
            ref.invalidate(publishingDashboardProvider);
          },
        ),
        title: Text(
          milestone.title,
          style: milestone.done
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(
          milestone.dueDate == null
              ? (milestone.notes.isEmpty ? 'No due date' : milestone.notes)
              : 'Due ${DateFormat.yMMMd().format(milestone.dueDate!)}'
                  '${milestone.notes.isEmpty ? '' : ' · ${milestone.notes}'}',
          style: TextStyle(color: _statusColor(context, status)),
        ),
        onTap: () => showEditMilestoneDialog(
          context,
          ref,
          project: project,
          milestone: milestone,
        ),
        trailing: IconButton(
          tooltip: 'Delete milestone',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final service = await ref.read(planningServiceProvider(project).future);
            await service.deleteMilestone(milestone.id);
            ref.invalidate(planningListProvider(project));
            ref.invalidate(notificationsProvider);
            ref.invalidate(publishingDashboardProvider);
          },
        ),
      ),
    );
  }
}

Future<void> showEditMilestoneDialog(
  BuildContext context,
  WidgetRef ref, {
  required Project project,
  PlanningMilestone? milestone,
}) {
  return showDialog(
    context: context,
    builder: (_) => _MilestoneDialog(project: project, milestone: milestone),
  );
}

class _MilestoneDialog extends ConsumerStatefulWidget {
  const _MilestoneDialog({required this.project, this.milestone});

  final Project project;
  final PlanningMilestone? milestone;

  @override
  ConsumerState<_MilestoneDialog> createState() => _MilestoneDialogState();
}

class _MilestoneDialogState extends ConsumerState<_MilestoneDialog> {
  late final _titleController =
      TextEditingController(text: widget.milestone?.title ?? '');
  late final _notesController =
      TextEditingController(text: widget.milestone?.notes ?? '');
  late DateTime? _dueDate = widget.milestone?.dueDate;
  late String? _linkedContactId = widget.milestone?.linkedContactId;

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final service = await ref.read(planningServiceProvider(widget.project).future);
    final existing = widget.milestone;
    if (existing == null) {
      await service.addMilestone(
        title: title,
        notes: _notesController.text.trim(),
        dueDate: _dueDate,
        linkedContactId: _linkedContactId,
      );
    } else {
      await service.updateMilestone(
        existing.copyWith(
          title: title,
          notes: _notesController.text.trim(),
          dueDate: _dueDate,
          clearDueDate: _dueDate == null,
          linkedContactId: _linkedContactId,
          clearLinkedContactId: _linkedContactId == null,
        ),
      );
    }
    ref.invalidate(planningListProvider(widget.project));
    ref.invalidate(notificationsProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactListProvider);

    return AlertDialog(
      title: Text(widget.milestone == null ? 'New Milestone' : 'Edit Milestone'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _dueDate == null
                        ? 'No due date'
                        : DateFormat.yMMMd().format(_dueDate!),
                  ),
                ),
                TextButton(onPressed: _pickDate, child: const Text('Pick date')),
                if (_dueDate != null)
                  IconButton(
                    tooltip: 'Clear date',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _dueDate = null),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            contactsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (err, stack) => const SizedBox.shrink(),
              data: (contacts) => DropdownButtonFormField<String?>(
                initialValue: _linkedContactId,
                decoration: const InputDecoration(labelText: 'Linked contact (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  for (final Contact contact in contacts)
                    DropdownMenuItem(value: contact.id, child: Text(contact.name)),
                ],
                onChanged: (id) => setState(() => _linkedContactId = id),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
