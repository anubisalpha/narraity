/// How many Drive network calls (file uploads/downloads, `project.json`
/// peeks) run at once — high enough to actually matter for a project with
/// dozens of files, low enough not to look like an automated burst to
/// Drive's per-user rate limiting.
const driveSyncConcurrency = 6;

/// Runs [action] over [items] with at most [concurrency] calls in flight at
/// once, preserving [items]' order in the result — the difference between a
/// project sync feeling like "copying a few files" and feeling like it's
/// stuck, since Drive sync/restore was previously awaiting one network
/// round-trip at a time in a plain loop (found live: restoring a manuscript
/// with dozens of scene files took noticeably longer than it should have).
///
/// Deliberately simple batch-of-[concurrency] chunking rather than a true
/// work-stealing pool — a slower file in one batch briefly holds up the
/// next batch's start, but that's a minor cost against not pulling in a
/// dependency (`pool`/`async`'s `Pool`) for what's otherwise a few lines,
/// and Drive API round-trips are similar enough in duration for this project
/// (small JSON/text files, not a mix of huge and tiny) that it doesn't
/// matter in practice.
Future<List<R>> mapConcurrently<T, R>(
  List<T> items,
  int concurrency,
  Future<R> Function(T item) action,
) async {
  final results = <R>[];
  for (var i = 0; i < items.length; i += concurrency) {
    final batch = items.skip(i).take(concurrency);
    results.addAll(await Future.wait(batch.map(action)));
  }
  return results;
}
