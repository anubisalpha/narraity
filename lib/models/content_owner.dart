import 'package:path/path.dart' as p;

import 'project.dart';
import 'series.dart';

/// Whatever a shared-content panel (characters, worldbuilding, story notes,
/// to-dos) is attached to: a single project, or — new — a series, shared
/// across every project inside it. `NotesPanel`/`ProfilePanel`/`TodoPanel`
/// and their providers were originally built around `Project` directly;
/// this is the seam that let them serve a `Series` too without duplicating
/// any of that widget/provider code, since the underlying services
/// (`StoryNotesService`, `ProfileService`, `TodoService`) already just take
/// a plain `Directory` and never cared which kind of owner it was.
sealed class ContentOwner {
  const ContentOwner();

  const factory ContentOwner.project(Project project) = ProjectOwner;
  const factory ContentOwner.series(Series series) = SeriesOwner;

  /// This owner's content directory, relative to the library root —
  /// resolve against `LibraryService.libraryRoot()` the same way a
  /// project's own folder is.
  String get relativePath;

  /// Display name for headers/empty-states.
  String get title;

  /// Non-null only for a [ProjectOwner].
  Project? get projectOrNull;

  /// Non-null only for a [SeriesOwner].
  Series? get seriesOrNull;
}

class ProjectOwner extends ContentOwner {
  const ProjectOwner(this.project);

  final Project project;

  @override
  String get relativePath => project.folderName;

  @override
  String get title => project.title;

  @override
  Project? get projectOrNull => project;

  @override
  Series? get seriesOrNull => null;

  @override
  bool operator ==(Object other) => other is ProjectOwner && other.project == project;

  @override
  int get hashCode => Object.hash(ProjectOwner, project);
}

class SeriesOwner extends ContentOwner {
  const SeriesOwner(this.series);

  final Series series;

  // A reserved folder alongside project folders, keyed by series id (not
  // title, which can change) — same `_`-prefixed convention as `_Vault`,
  // `_GlobalIdeas`, etc., all of which `LibraryService.listProjects`
  // already skips when scanning for projects.
  @override
  String get relativePath => p.join('_Series', 'series-${series.id}');

  @override
  String get title => series.title;

  @override
  Project? get projectOrNull => null;

  @override
  Series? get seriesOrNull => series;

  @override
  bool operator ==(Object other) => other is SeriesOwner && other.series == series;

  @override
  int get hashCode => Object.hash(SeriesOwner, series);
}
