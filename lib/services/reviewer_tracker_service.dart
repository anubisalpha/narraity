import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/reviewer_send.dart';

const _uuid = Uuid();

/// Reads/writes a project's `planning/reviewers.json`.
class ReviewerTrackerService {
  ReviewerTrackerService(this.projectDir);

  final Directory projectDir;

  File get _file => File(p.join(projectDir.path, 'planning', 'reviewers.json'));

  Future<List<ReviewerSend>> listSends() async {
    if (!await _file.exists()) return [];
    try {
      final json = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      return (json['reviewers'] as List<dynamic>? ?? [])
          .map((r) => ReviewerSend.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<ReviewerSend> addSend({
    required String contactId,
    String format = '',
    required DateTime dateSent,
    DateTime? targetDeadline,
  }) async {
    final sends = await listSends();
    final send = ReviewerSend(
      id: 'reviewer-send-${_uuid.v4()}',
      contactId: contactId,
      format: format,
      dateSent: dateSent,
      targetDeadline: targetDeadline,
    );
    sends.add(send);
    await _save(sends);
    return send;
  }

  Future<void> updateSend(ReviewerSend updated) async {
    final sends = await listSends();
    final index = sends.indexWhere((s) => s.id == updated.id);
    if (index == -1) return;
    sends[index] = updated;
    await _save(sends);
  }

  Future<void> deleteSend(String id) async {
    final sends = await listSends();
    sends.removeWhere((s) => s.id == id);
    await _save(sends);
  }

  /// Average turnaround across returned sends, or null if none have
  /// returned yet.
  Future<double?> averageTurnaroundDays() async {
    final sends = await listSends();
    final turnarounds = sends
        .map((s) => s.turnaroundDays)
        .whereType<int>()
        .toList();
    if (turnarounds.isEmpty) return null;
    return turnarounds.reduce((a, b) => a + b) / turnarounds.length;
  }

  Future<void> _save(List<ReviewerSend> sends) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'reviewers': sends.map((s) => s.toJson()).toList(),
    }));
  }
}
