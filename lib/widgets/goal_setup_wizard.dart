import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/goal.dart';
import '../models/project.dart';
import '../services/goal_calculator.dart';
import '../state/goals_provider.dart';

const _weekdayLabels = {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};

/// Per-project goal creation — always scopes to the whole project (see
/// GoalScope's doc comment for why act/scene-level goals were dropped).
/// PLAN.md's stated order: target type -> deadline/count -> working days ->
/// live preview, laid out as one scrollable form rather than a literal
/// multi-page wizard so the live preview reacts to every field as it's
/// edited.
Future<void> showGoalSetupWizard(
  BuildContext context,
  WidgetRef ref,
  Project project,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _GoalSetupDialog(project: project),
  );
}

class _GoalSetupDialog extends ConsumerStatefulWidget {
  const _GoalSetupDialog({required this.project});

  final Project project;

  @override
  ConsumerState<_GoalSetupDialog> createState() => _GoalSetupDialogState();
}

class _GoalSetupDialogState extends ConsumerState<_GoalSetupDialog> {
  GoalTargetType _targetType = GoalTargetType.deadline;
  final _wordCountController = TextEditingController(text: '80000');
  DateTime _deadline = DateTime.now().add(const Duration(days: 90));
  final Set<int> _daysOff = {};
  bool _saving = false;

  @override
  void dispose() {
    _wordCountController.dispose();
    super.dispose();
  }

  int get _targetWordCount => int.tryParse(_wordCountController.text) ?? 0;

  Future<void> _create() async {
    setState(() => _saving = true);
    final service = await ref.read(goalsServiceProvider(widget.project).future);
    await service.createGoal(
      targetType: _targetType,
      targetWordCount: _targetWordCount,
      deadline: _deadline,
      calendar: WorkingCalendar(recurringDaysOff: _daysOff),
    );
    ref.invalidate(goalListProvider(widget.project));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Goal'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Target type', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              SegmentedButton<GoalTargetType>(
                segments: const [
                  ButtonSegment(
                    value: GoalTargetType.wordCount,
                    label: Text('Word count'),
                  ),
                  ButtonSegment(value: GoalTargetType.deadline, label: Text('Deadline')),
                ],
                selected: {_targetType},
                onSelectionChanged: (s) => setState(() => _targetType = s.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _wordCountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Target word count'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Deadline: ${_deadline.year}-${_deadline.month.toString().padLeft(2, '0')}-${_deadline.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _deadline,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                      );
                      if (picked != null) setState(() => _deadline = picked);
                    },
                    child: const Text('Change'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Working calendar', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: [
                  for (final weekday in _weekdayLabels.keys)
                    FilterChip(
                      label: Text(_weekdayLabels[weekday]!),
                      selected: _daysOff.contains(weekday),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _daysOff.add(weekday);
                        } else {
                          _daysOff.remove(weekday);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Tap days you don\'t write on — targets redistribute around them.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 32),
              _LivePreview(
                project: widget.project,
                targetWordCount: _targetWordCount,
                deadline: _deadline,
                daysOff: _daysOff,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_saving || _targetWordCount <= 0) ? null : _create,
          child: const Text('Create Goal'),
        ),
      ],
    );
  }
}

class _LivePreview extends ConsumerWidget {
  const _LivePreview({
    required this.project,
    required this.targetWordCount,
    required this.deadline,
    required this.daysOff,
  });

  final Project project;
  final int targetWordCount;
  final DateTime deadline;
  final Set<int> daysOff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(goalsServiceProvider(project));

    return servicesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (err, stack) => const SizedBox.shrink(),
      data: (service) => FutureBuilder<int>(
        future: service.currentWordCount(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || targetWordCount <= 0) {
            return const SizedBox.shrink();
          }
          final starting = snapshot.data!;
          final previewGoal = Goal(
            id: 'preview',
            scope: GoalScope.project,
            targetType: GoalTargetType.deadline,
            targetWordCount: targetWordCount,
            deadline: deadline,
            startingWordCount: starting,
            created: DateTime.now(),
            calendar: WorkingCalendar(recurringDaysOff: daysOff),
          );
          final progress = GoalCalculator.calculate(
            goal: previewGoal,
            currentWordCount: starting,
            today: DateTime.now(),
          );

          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Preview', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text('${progress.remainingWords} words to write'),
                Text('${progress.remainingWorkingDays} working days until deadline'),
                Text(
                  '${progress.dailyTarget} words/day to hit your goal',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
