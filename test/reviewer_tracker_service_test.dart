import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/reviewer_send.dart';
import 'package:narraity/services/reviewer_tracker_service.dart';

void main() {
  late Directory tempDir;
  late ReviewerTrackerService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_reviewer_tracker_test_');
    service = ReviewerTrackerService(tempDir);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('a fresh project has no reviewer sends', () async {
    expect(await service.listSends(), isEmpty);
  });

  test('addSend persists to planning/reviewers.json and round-trips', () async {
    final sent = DateTime(2026, 1, 1);
    final send = await service.addSend(
      contactId: 'contact-1',
      format: 'EPUB',
      dateSent: sent,
      targetDeadline: DateTime(2026, 1, 15),
    );

    expect(File('${tempDir.path}/planning/reviewers.json').existsSync(), isTrue);
    final sends = await service.listSends();
    expect(sends.single.contactId, 'contact-1');
    expect(sends.single.format, 'EPUB');
    expect(sends.single.dateSent, sent);
    expect(sends.single.id, send.id);
  });

  test('updateSend records a return and turnaroundDays is computed', () async {
    final send = await service.addSend(
      contactId: 'contact-1',
      dateSent: DateTime(2026, 1, 1),
    );
    await service.updateSend(send.copyWith(dateReturned: DateTime(2026, 1, 19)));

    final reloaded = (await service.listSends()).single;
    expect(reloaded.turnaroundDays, 18);
  });

  test('deleteSend removes only the targeted send', () async {
    final keep = await service.addSend(contactId: 'keep', dateSent: DateTime(2026, 1, 1));
    final drop = await service.addSend(contactId: 'drop', dateSent: DateTime(2026, 1, 1));

    await service.deleteSend(drop.id);

    final remaining = await service.listSends();
    expect(remaining.single.id, keep.id);
  });

  test('averageTurnaroundDays averages only returned sends', () async {
    final a = await service.addSend(contactId: 'a', dateSent: DateTime(2026, 1, 1));
    await service.updateSend(a.copyWith(dateReturned: DateTime(2026, 1, 11))); // 10 days
    final b = await service.addSend(contactId: 'b', dateSent: DateTime(2026, 1, 1));
    await service.updateSend(b.copyWith(dateReturned: DateTime(2026, 1, 21))); // 20 days
    await service.addSend(contactId: 'c', dateSent: DateTime(2026, 1, 1)); // not returned

    expect(await service.averageTurnaroundDays(), 15);
  });

  group('statusAsOf', () {
    final now = DateTime(2026, 6, 15);

    test('declined overrides everything else', () {
      final send = ReviewerSend(
        id: 's1',
        contactId: 'c1',
        dateSent: DateTime(2026, 1, 1),
        dateReturned: DateTime(2026, 1, 10),
        declined: true,
      );
      expect(send.statusAsOf(now), ReviewerSendStatus.declined);
    });

    test('a returned send is returned even past its deadline', () {
      final send = ReviewerSend(
        id: 's1',
        contactId: 'c1',
        dateSent: DateTime(2026, 1, 1),
        targetDeadline: DateTime(2026, 1, 15),
        dateReturned: DateTime(2026, 2, 1),
      );
      expect(send.statusAsOf(now), ReviewerSendStatus.returned);
    });

    test('past deadline with nothing returned is overdue', () {
      final send = ReviewerSend(
        id: 's1',
        contactId: 'c1',
        dateSent: DateTime(2026, 1, 1),
        targetDeadline: DateTime(2026, 6, 1),
      );
      expect(send.statusAsOf(now), ReviewerSendStatus.overdue);
    });

    test('no deadline yet is in progress', () {
      final send = ReviewerSend(id: 's1', contactId: 'c1', dateSent: DateTime(2026, 1, 1));
      expect(send.statusAsOf(now), ReviewerSendStatus.inProgress);
    });
  });
}
