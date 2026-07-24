import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/snapshot_pruner.dart';

void main() {
  final now = DateTime(2026, 7, 24, 12, 0, 0);

  test('empty input keeps nothing', () {
    expect(SnapshotPruner.selectToKeep([], now), isEmpty);
  });

  test('everything within 48h is kept, regardless of density', () {
    final timestamps = List.generate(
      20,
      (i) => now.subtract(Duration(hours: i)), // 0..19 hours ago
    );
    final kept = SnapshotPruner.selectToKeep(timestamps, now);
    expect(kept, timestamps.toSet());
  });

  test('48h-7d window thins to one per hour', () {
    final hourAgo = now.subtract(const Duration(days: 3));
    final timestamps = [
      hourAgo,
      hourAgo.add(const Duration(minutes: 15)),
      hourAgo.add(const Duration(minutes: 45)),
      hourAgo.add(const Duration(hours: 1)), // different hour bucket
    ];
    final kept = SnapshotPruner.selectToKeep(timestamps, now);
    // Only the first snapshot of each distinct hour survives.
    expect(kept, {timestamps[0], timestamps[3]});
  });

  test('7d-30d window thins to one per day', () {
    final dayAgo = now.subtract(const Duration(days: 15));
    final timestamps = [
      DateTime(dayAgo.year, dayAgo.month, dayAgo.day, 9),
      DateTime(dayAgo.year, dayAgo.month, dayAgo.day, 14),
      DateTime(dayAgo.year, dayAgo.month, dayAgo.day, 20),
    ];
    final kept = SnapshotPruner.selectToKeep(timestamps, now);
    // First-of-day survives via the daily bucket; the last timestamp also
    // survives separately because it's the single most recent snapshot
    // overall ("current state" is never pruned — see the dedicated test
    // for that invariant below).
    expect(kept, {timestamps.first, timestamps.last});
  });

  test('older than 30d thins to one per week', () {
    final base = now.subtract(const Duration(days: 60));
    final timestamps = [
      base,
      base.add(const Duration(days: 1)),
      base.add(const Duration(days: 2)),
      base.add(const Duration(days: 10)), // a different ISO week
    ];
    final kept = SnapshotPruner.selectToKeep(timestamps, now);
    expect(kept, hasLength(2));
    expect(kept, contains(base));
    expect(kept, contains(timestamps.last));
  });

  test('the single most recent snapshot always survives, however old', () {
    // All four snapshots land in the same weekly bucket, so naive thinning
    // would keep only the earliest — but the latest one is "current state"
    // and must never be pruned away.
    final base = now.subtract(const Duration(days: 60));
    final timestamps = [
      base,
      base.add(const Duration(hours: 1)),
      base.add(const Duration(hours: 2)),
      base.add(const Duration(hours: 3)),
    ];
    final kept = SnapshotPruner.selectToKeep(timestamps, now);
    expect(kept, contains(timestamps.last));
  });

  test('mixed ages across every tier prune independently', () {
    final recent = now.subtract(const Duration(hours: 1));
    final weekOldA = now.subtract(const Duration(days: 3, hours: 1));
    final weekOldB = weekOldA.add(const Duration(minutes: 20)); // same clock hour
    final monthOldA = now.subtract(const Duration(days: 10));
    final monthOldB = DateTime(monthOldA.year, monthOldA.month, monthOldA.day, 22);

    final kept = SnapshotPruner.selectToKeep(
      [recent, weekOldA, weekOldB, monthOldA, monthOldB],
      now,
    );

    expect(kept, contains(recent)); // always kept, <48h
    expect(kept, contains(weekOldA)); // first in its hour bucket
    expect(kept, isNot(contains(weekOldB))); // same hour bucket, pruned
    expect(kept, contains(monthOldA)); // first in its day bucket
    expect(kept, isNot(contains(monthOldB))); // same day, pruned
  });
}
