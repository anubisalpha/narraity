import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../state/goals_provider.dart';
import '../widgets/goal_progress_card.dart';
import '../widgets/goal_setup_wizard.dart';

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(goalListProvider(project));

    return Scaffold(
      appBar: AppBar(title: const Text('Goals')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showGoalSetupWizard(context, ref, project),
        icon: const Icon(Icons.add),
        label: const Text('New Goal'),
      ),
      body: goalsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Failed to load goals: $err')),
        data: (goals) => goals.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flag_outlined,
                        size: 72, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text('No goals yet', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text('Set a word-count or deadline goal to get daily targets.'),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                children: [
                  for (final goal in goals.where((g) => g.active))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: GoalProgressCard(
                        goal: goal,
                        onRecordProgress: (g) async {
                          final service =
                              await ref.read(goalsServiceProvider(project).future);
                          return service.recordTodaysProgress(g);
                        },
                        onDelete: (g) async {
                          final service =
                              await ref.read(goalsServiceProvider(project).future);
                          await service.deleteGoal(g.id);
                          ref.invalidate(goalListProvider(project));
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
