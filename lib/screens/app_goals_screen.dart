import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/global_goals_provider.dart';
import '../widgets/global_goal_setup_wizard.dart';
import '../widgets/goal_progress_card.dart';

/// App-wide goals — track word count across multiple (or all) projects.
/// Per-project goals (project/act/scene scope) live inside each project's
/// own Goals screen instead; this is the "global" counterpart.
class AppGoalsScreen extends ConsumerWidget {
  const AppGoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(globalGoalListProvider);
    final service = ref.watch(globalGoalsServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('App-Wide Goals')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showGlobalGoalSetupWizard(context, ref),
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
                    Icon(Icons.flag_circle_outlined,
                        size: 72, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text('No app-wide goals yet',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text(
                      'Track a target across all your projects — or just the ones you pick.',
                      textAlign: TextAlign.center,
                    ),
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
                        onRecordProgress: service.recordTodaysProgress,
                        onDelete: (g) async {
                          await service.deleteGoal(g.id);
                          ref.invalidate(globalGoalListProvider);
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
