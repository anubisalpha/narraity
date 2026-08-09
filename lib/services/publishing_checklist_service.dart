import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/publishing_checklist_state.dart';

/// Reads/writes a project's `planning/publishing_checklist.json`.
class PublishingChecklistService {
  PublishingChecklistService(this.projectDir);

  final Directory projectDir;

  File get _file =>
      File(p.join(projectDir.path, 'planning', 'publishing_checklist.json'));

  Future<PublishingChecklistState> load() async {
    if (!await _file.exists()) return PublishingChecklistState();
    try {
      final json = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      return PublishingChecklistState.fromJson(json);
    } catch (_) {
      return PublishingChecklistState();
    }
  }

  Future<void> save(PublishingChecklistState state) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
    );
  }
}
