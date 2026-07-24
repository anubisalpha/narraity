import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/goal.dart';
import '../models/project.dart';
import '../services/goal_calculator.dart';
import '../state/global_goals_provider.dart';
import '../state/library_provider.dart';

const _weekdayLabels = {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};

/// App-wide goal creation — same field order as the per-project wizard
/// (target type -> count/deadline -> working days -> live preview), but the
/// scope step becomes "which projects count toward this" instead of
/// act/scene, since a global goal isn't rooted in one project's manuscript.
Future<void> showGlobalGoalSetupWizard(BuildContext context, WidgetRef ref) async {
  await showDialog<void>(
    context: context,
    builder: (context) => const _GlobalGoalSetupDialog(),
  );
}

class _GlobalGoalSetupDialog extends ConsumerStatefulWidget {
  const _GlobalGoalSetupDialog();

  @override
  ConsumerState<_GlobalGoalSetupDialog> createState() => _GlobalGoalSetupDialogState();
}

class _GlobalGoalSetupDialogState extends ConsumerState<_GlobalGoalSetupDialog> {
  bool _allProjects = true;
  final Set<String> _selectedProjectIds = {};
  GoalTargetType _targetType = GoalTargetType.deadline;
  final _wordCountController = TextEditingController(text: '1000000');
  DateTime _deadline = DateTime.now().add(const Duration(days: 365));
  final Set<int> _daysOff = {};
  bool _saving = false;

  @override
  void dispose() {
    _wordCountController.dispose();
    super.dispose();
  }

  int get _targetWordCount => int.tryParse(_wordCountController.text) ?? 0;

  List<String>? get _projectIds => _allProjects ? null : _selectedProjectIds.toList();

  Future<void> _create() async {
    setState(() => _saving = true);
    final service = ref.read(globalGoalsServiceProvider);
    await service.createGoal(
      targetType: _targetType,
      targetWordCount: _targetWordCount,
      deadline: _deadline,
      projectIds: _projectIds,
      calendar: WorkingCalendar(recurringDaysOff: _daysOff),
    );
    ref.invalidate(globalGoalListProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectListProvider);

    return AlertDialog(
      title: const Text('New App-Wide Goal'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Which projects count?', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              projectsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (err, stack) => Text('Could not load projects: $err'),
                data: (projects) => _ProjectPicker(
                  projects: projects,
                  allProjects: _allProjects,
                  selectedIds: _selectedProjectIds,
                  onAllToggled: (all) => setState(() => _allProjects = all),
                  onProjectToggled: (id, selected) => setState(() {
                    if (selected) {
                      _selectedProjectIds.add(id);
                    } else {
                      _selectedProjectIds.remove(id);
                    }
                  }),
                ),
              ),
              const SizedBox(height: 16),
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
                        lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
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
              const Divider(height: 32),
              _LivePreview(
                targetWordCount: _targetWordCount,
                deadline: _deadline,
                daysOff: _daysOff,
                projectIds: _projectIds,
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
          onPressed: (_saving ||
                  _targetWordCount <= 0 ||
                  (!_allProjects && _selectedProjectIds.isEmpty))
              ? null
              : _create,
          child: const Text('Create Goal'),
        ),
      ],
    );
  }
}

class _ProjectPicker extends StatelessWidget {
  const _ProjectPicker({
    required this.projects,
    required this.allProjects,
    required this.selectedIds,
    required this.onAllToggled,
    required this.onProjectToggled,
  });

  final List<Project> projects;
  final bool allProjects;
  final Set<String> selectedIds;
  final void Function(bool allProjects) onAllToggled;
  final void Function(String projectId, bool selected) onProjectToggled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('All projects')),
            ButtonSegment(value: false, label: Text('Specific projects')),
          ],
          selected: {allProjects},
          onSelectionChanged: (s) => onAllToggled(s.first),
        ),
        if (!allProjects) ...[
          const SizedBox(height: 8),
          if (projects.isEmpty)
            const Text('No projects yet.')
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final project in projects)
                  FilterChip(
                    label: Text(project.title),
                    selected: selectedIds.contains(project.id),
                    onSelected: (selected) => onProjectToggled(project.id, selected),
                  ),
              ],
            ),
        ],
      ],
    );
  }
}

class _LivePreview extends ConsumerWidget {
  const _LivePreview({
    required this.targetWordCount,
    required this.deadline,
    required this.daysOff,
    required this.projectIds,
  });

  final int targetWordCount;
  final DateTime deadline;
  final Set<int> daysOff;
  final List<String>? projectIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(globalGoalsServiceProvider);

    return FutureBuilder<int>(
      future: service.currentWordCount(projectIds),
      builder: (context, snapshot) {
        if (!snapshot.hasData || targetWordCount <= 0) {
          return const SizedBox.shrink();
        }
        final starting = snapshot.data!;
        final previewGoal = Goal(
          id: 'preview',
          scope: GoalScope.global,
          projectIds: projectIds,
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
    );
  }
}
