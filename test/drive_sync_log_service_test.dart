import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/sync_log_entry.dart';
import 'package:narraity/services/drive_sync_log_service.dart';

void main() {
  late Directory root;
  late DriveSyncLogService service;

  setUp(() {
    root = Directory.systemTemp.createTempSync('narraity_sync_log_test_');
    service = DriveSyncLogService(rootOverride: root);
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  test('readRecent returns empty when nothing logged yet', () async {
    expect(await service.readRecent(), isEmpty);
  });

  test('append then readRecent round-trips, most recent first', () async {
    await service.append(SyncLogEntry(
      timestamp: DateTime.utc(2026, 1, 1),
      targetTitle: 'My Novel',
      trigger: SyncTrigger.manual,
      uploaded: 2,
    ));
    await service.append(SyncLogEntry(
      timestamp: DateTime.utc(2026, 1, 2),
      targetTitle: 'Vault backups',
      trigger: SyncTrigger.periodic,
      downloaded: 1,
    ));

    final entries = await service.readRecent();
    expect(entries, hasLength(2));
    expect(entries.first.targetTitle, 'Vault backups'); // most recent first
    expect(entries.first.trigger, SyncTrigger.periodic);
    expect(entries.last.targetTitle, 'My Novel');
    expect(entries.last.uploaded, 2);
  });

  test('an error entry round-trips its error text', () async {
    await service.append(SyncLogEntry(
      timestamp: DateTime.utc(2026, 1, 1),
      targetTitle: 'My Novel',
      trigger: SyncTrigger.immediate,
      error: 'network unreachable',
    ));

    final entries = await service.readRecent();
    expect(entries.single.error, 'network unreachable');
  });

  test('trims to maxEntries, dropping the oldest first', () async {
    for (var i = 0; i < DriveSyncLogService.maxEntries + 10; i++) {
      await service.append(SyncLogEntry(
        timestamp: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
        targetTitle: 'Entry $i',
        trigger: SyncTrigger.manual,
      ));
    }

    final entries = await service.readRecent();
    expect(entries, hasLength(DriveSyncLogService.maxEntries));
    // The oldest 10 (Entry 0..9) should have been dropped; the newest
    // survives at the front.
    expect(entries.first.targetTitle, 'Entry ${DriveSyncLogService.maxEntries + 9}');
    expect(entries.any((e) => e.targetTitle == 'Entry 0'), isFalse);
  });

  test('clear removes all entries', () async {
    await service.append(SyncLogEntry(
      timestamp: DateTime.now(),
      targetTitle: 'My Novel',
      trigger: SyncTrigger.manual,
    ));
    await service.clear();

    expect(await service.readRecent(), isEmpty);
  });

  test('a corrupt log file is treated as empty rather than throwing', () async {
    final logFile = await service.readRecent(); // ensure dir logic exercised
    expect(logFile, isEmpty);

    await root.create(recursive: true);
    await File('${root.path}/log.json').writeAsString('not valid json{{{');

    expect(await service.readRecent(), isEmpty);
  });
}
