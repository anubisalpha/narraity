import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/data/publishing_guidance.dart';
import 'package:narraity/models/publishing_checklist_state.dart';
import 'package:narraity/services/publishing_checklist_service.dart';

void main() {
  late Directory tempDir;
  late PublishingChecklistService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_publishing_checklist_test_');
    service = PublishingChecklistService(tempDir);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('a fresh project has default (empty) checklist state', () async {
    final state = await service.load();
    expect(state.selectedRoute, isNull);
    expect(state.genre, isEmpty);
    expect(state.checkedItemIds, isEmpty);
  });

  test('save persists route, genre, and checked items, then round-trips', () async {
    final state = PublishingChecklistState(
      selectedRoute: PublishingRoute.selfPublishing,
      genre: 'Fantasy',
      checkedItemIds: {'beta-reader-pass', 'manuscript-polish'},
    );
    await service.save(state);

    expect(
      File('${tempDir.path}/planning/publishing_checklist.json').existsSync(),
      isTrue,
    );
    final reloaded = await service.load();
    expect(reloaded.selectedRoute, PublishingRoute.selfPublishing);
    expect(reloaded.genre, 'Fantasy');
    expect(reloaded.checkedItemIds, {'beta-reader-pass', 'manuscript-polish'});
  });

  test('a corrupt file falls back to default state rather than throwing', () async {
    final file = File('${tempDir.path}/planning/publishing_checklist.json');
    await file.create(recursive: true);
    await file.writeAsString('not valid json');

    final state = await service.load();
    expect(state.selectedRoute, isNull);
    expect(state.checkedItemIds, isEmpty);
  });
}
