import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/goal.dart';
import '../services/global_goals_service.dart';
import 'library_provider.dart';

final globalGoalsServiceProvider = Provider<GlobalGoalsService>(
  (ref) => GlobalGoalsService(ref.watch(libraryServiceProvider)),
);

final globalGoalListProvider = FutureProvider<List<Goal>>((ref) async {
  final service = ref.watch(globalGoalsServiceProvider);
  return service.listGoals();
});
