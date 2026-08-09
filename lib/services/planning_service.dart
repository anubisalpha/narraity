import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/planning_milestone.dart';

const _uuid = Uuid();

/// Reads/writes a project's `planning/milestones.json`.
class PlanningService {
  PlanningService(this.projectDir);

  final Directory projectDir;

  File get _file => File(p.join(projectDir.path, 'planning', 'milestones.json'));

  Future<List<PlanningMilestone>> listMilestones() async {
    if (!await _file.exists()) return [];
    try {
      final json = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      return (json['milestones'] as List<dynamic>? ?? [])
          .map((m) => PlanningMilestone.fromJson(m as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<PlanningMilestone> addMilestone({
    required String title,
    String notes = '',
    DateTime? dueDate,
    int reminderDaysBefore = 7,
    String? linkedContactId,
  }) async {
    final milestones = await listMilestones();
    final milestone = PlanningMilestone(
      id: 'milestone-${_uuid.v4()}',
      title: title,
      notes: notes,
      dueDate: dueDate,
      reminderDaysBefore: reminderDaysBefore,
      linkedContactId: linkedContactId,
    );
    milestones.add(milestone);
    await _save(milestones);
    return milestone;
  }

  Future<void> updateMilestone(PlanningMilestone updated) async {
    final milestones = await listMilestones();
    final index = milestones.indexWhere((m) => m.id == updated.id);
    if (index == -1) return;
    milestones[index] = updated;
    await _save(milestones);
  }

  Future<void> deleteMilestone(String id) async {
    final milestones = await listMilestones();
    milestones.removeWhere((m) => m.id == id);
    await _save(milestones);
  }

  Future<void> _save(List<PlanningMilestone> milestones) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'milestones': milestones.map((m) => m.toJson()).toList(),
    }));
  }
}
