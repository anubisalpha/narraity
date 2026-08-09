import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/planning_milestone.dart';
import 'package:narraity/services/planning_service.dart';

void main() {
  late Directory tempDir;
  late PlanningService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_planning_test_');
    service = PlanningService(tempDir);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('a fresh project has no milestones', () async {
    expect(await service.listMilestones(), isEmpty);
  });

  test('addMilestone persists to planning/milestones.json and round-trips', () async {
    final due = DateTime(2026, 12, 1);
    final milestone = await service.addMilestone(title: 'Query package due', dueDate: due);

    expect(File('${tempDir.path}/planning/milestones.json').existsSync(), isTrue);
    final milestones = await service.listMilestones();
    expect(milestones.single.title, 'Query package due');
    expect(milestones.single.dueDate, due);
    expect(milestones.single.id, milestone.id);
  });

  test('updateMilestone toggles done state', () async {
    final milestone = await service.addMilestone(title: 'Send to betas');
    await service.updateMilestone(milestone.copyWith(done: true));

    final reloaded = await service.listMilestones();
    expect(reloaded.single.done, isTrue);
  });

  test('deleteMilestone removes only the targeted item', () async {
    final keep = await service.addMilestone(title: 'Keep me');
    final drop = await service.addMilestone(title: 'Delete me');

    await service.deleteMilestone(drop.id);

    final remaining = await service.listMilestones();
    expect(remaining.single.id, keep.id);
  });

  group('statusAsOf', () {
    final now = DateTime(2026, 6, 15);

    test('done milestones are always done, regardless of due date', () {
      final milestone = PlanningMilestone(
        id: 'm1',
        title: 'x',
        dueDate: DateTime(2020),
        done: true,
      );
      expect(milestone.statusAsOf(now), PlanningMilestoneStatus.done);
    });

    test('a past due date with done=false is overdue', () {
      final milestone =
          PlanningMilestone(id: 'm1', title: 'x', dueDate: DateTime(2026, 6, 1));
      expect(milestone.statusAsOf(now), PlanningMilestoneStatus.overdue);
    });

    test('within reminderDaysBefore of the due date is dueSoon', () {
      final milestone = PlanningMilestone(
        id: 'm1',
        title: 'x',
        dueDate: DateTime(2026, 6, 18),
        reminderDaysBefore: 7,
      );
      expect(milestone.statusAsOf(now), PlanningMilestoneStatus.dueSoon);
    });

    test('far in the future is upcoming', () {
      final milestone = PlanningMilestone(
        id: 'm1',
        title: 'x',
        dueDate: DateTime(2026, 12, 1),
        reminderDaysBefore: 7,
      );
      expect(milestone.statusAsOf(now), PlanningMilestoneStatus.upcoming);
    });

    test('no due date is upcoming', () {
      final milestone = PlanningMilestone(id: 'm1', title: 'x');
      expect(milestone.statusAsOf(now), PlanningMilestoneStatus.upcoming);
    });
  });
}
