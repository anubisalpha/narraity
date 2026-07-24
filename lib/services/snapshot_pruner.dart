/// Decides which auto-snapshot timestamps survive pruning (PLAN.md
/// "Pruning policy"): everything from the last 48h is kept; 48h–7d thins to
/// one per hour; 7d–30d thins to one per day; older than 30d thins to one
/// per week. Checkpoints are never passed in here — they're always kept,
/// handled entirely by SceneHistoryService excluding them from pruning.
///
/// Pure and deterministic — takes "now" as a parameter so it's fully
/// unit-testable without touching the clock or disk.
class SnapshotPruner {
  SnapshotPruner._();

  static Set<DateTime> selectToKeep(List<DateTime> timestamps, DateTime now) {
    final sorted = [...timestamps]..sort();
    final kept = <DateTime>{};
    DateTime? lastKeptInBucket;
    String? lastBucketKey;

    for (final ts in sorted) {
      final age = now.difference(ts);

      if (age <= const Duration(hours: 48)) {
        kept.add(ts);
        continue;
      }

      final String bucketKey;
      if (age <= const Duration(days: 7)) {
        bucketKey = 'h-${ts.year}-${ts.month}-${ts.day}-${ts.hour}';
      } else if (age <= const Duration(days: 30)) {
        bucketKey = 'd-${ts.year}-${ts.month}-${ts.day}';
      } else {
        bucketKey = 'w-${_isoWeek(ts)}';
      }

      if (bucketKey != lastBucketKey) {
        kept.add(ts);
        lastBucketKey = bucketKey;
        lastKeptInBucket = ts;
      } else {
        // Already kept the first snapshot in this bucket — skip this one.
        assert(lastKeptInBucket != null);
      }
    }

    // The single most recent snapshot must always survive, however old it
    // is — it's "the current state." Thinning is for old *intermediate*
    // history, never for the tip: losing it would mean reconstructContent
    // silently reverts to a stale point even though nothing was deleted on
    // purpose.
    if (sorted.isNotEmpty) kept.add(sorted.last);

    return kept;
  }

  /// (ISO year, ISO week number) as a comparable key.
  static String _isoWeek(DateTime date) {
    final thursday = date.add(Duration(days: 3 - ((date.weekday + 6) % 7)));
    final firstDayOfYear = DateTime(thursday.year, 1, 1);
    final week = ((thursday.difference(firstDayOfYear).inDays) / 7).floor() + 1;
    return '${thursday.year}-$week';
  }
}
