import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A filesystem change, decoupled from `dart:io`'s sealed `FileSystemEvent`
/// (which has no public constructor, so tests can't build one directly) —
/// lets [ProjectFileWatcher] be driven by a synthetic stream in tests.
class ProjectFileChangeEvent {
  const ProjectFileChangeEvent(this.path, {this.isDirectory = false});
  final String path;
  final bool isDirectory;
}

/// Watches a project folder for file changes and, after a short per-path
/// debounce, reports the changed file's path relative to the project
/// folder — what drives "sync immediately after saving" without hooking a
/// sync call into every place the app writes a file (scenes, characters,
/// world entries, notes, todos, goals, plot grid, timeline, relationships,
/// annotations, ...). One filesystem watch catches all of them uniformly.
///
/// [events] is injectable (defaults to wrapping
/// `projectDir.watch(recursive: true)`) so tests can feed synthetic events
/// instead of depending on real OS-level notifications and their timing.
class ProjectFileWatcher {
  ProjectFileWatcher(
    this.projectDir, {
    required this.onFileChanged,
    Stream<ProjectFileChangeEvent>? events,
    this.debounce = const Duration(seconds: 2),
  }) {
    final source = events ??
        projectDir.watch(recursive: true).map(
              (e) => ProjectFileChangeEvent(e.path, isDirectory: e.isDirectory),
            );
    _subscription = source.listen(_handleEvent);
  }

  final Directory projectDir;
  final void Function(String relativePath) onFileChanged;
  final Duration debounce;

  StreamSubscription<ProjectFileChangeEvent>? _subscription;
  final Map<String, Timer> _debounceTimers = {};

  void _handleEvent(ProjectFileChangeEvent event) {
    if (event.isDirectory) return; // only individual file changes matter here

    final relative = p.relative(event.path, from: projectDir.path);
    final segments = p.split(relative);
    if (segments.isEmpty || segments.first.isEmpty) return;
    // Same exclusions as SyncManifestService.hashLocalFiles — the manifest
    // itself and Version History's local-only corruption-insurance mirror
    // aren't sync targets, and watching them would risk feedback loops
    // (every sync run rewrites the manifest).
    if (segments.first == '.sync') return;
    if (segments.contains('.history_backup')) return;

    final posixPath = segments.join('/');
    _debounceTimers[posixPath]?.cancel();
    _debounceTimers[posixPath] = Timer(debounce, () {
      _debounceTimers.remove(posixPath);
      onFileChanged(posixPath);
    });
  }

  Future<void> dispose() async {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    await _subscription?.cancel();
  }
}
