import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/series.dart';
import 'library_service.dart';

const _uuid = Uuid();

/// Reads/writes `_Series/series-<id>.json` at the library root — one file
/// per series, alongside (not inside) project folders, same convention as
/// `_GlobalIdeas/` (see `ideas_service.dart`). A series is just a named
/// grouping; membership lives on each `Project.seriesId`, not here.
class SeriesService {
  SeriesService(this._library);

  final LibraryService _library;

  Future<Directory> _seriesDir() async {
    final root = await _library.libraryRoot();
    final dir = Directory(p.join(root.path, '_Series'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<Series>> listSeries() async {
    final dir = await _seriesDir();
    final series = <Series>[];

    await for (final entity in dir.list()) {
      if (entity is! File || !p.basename(entity.path).endsWith('.json')) continue;
      try {
        final json = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        series.add(Series.fromJson(json));
      } catch (_) {
        continue; // skip corrupt files rather than breaking the library view
      }
    }

    series.sort((a, b) => b.modified.compareTo(a.modified));
    return series;
  }

  Future<Series> createSeries({required String title}) async {
    final now = DateTime.now();
    final series = Series(id: _uuid.v4(), title: title, created: now, modified: now);
    await _write(series);
    return series;
  }

  Future<void> renameSeries(Series series, String title) async {
    await _write(series.copyWith(title: title, modified: DateTime.now()));
  }

  /// Persists arbitrary edits (e.g. `sortOrder` from drag-and-drop
  /// reordering) without touching `modified` — unlike a rename, reordering
  /// isn't "activity" on the series itself.
  Future<void> saveSeries(Series series) => _write(series);

  /// Deletes the series itself only — member projects are left alone
  /// (their `seriesId` becomes dangling and the library treats them as
  /// standalone again on next scan). Never deletes project data.
  Future<void> deleteSeries(Series series) async {
    final dir = await _seriesDir();
    final file = File(p.join(dir.path, 'series-${series.id}.json'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _write(Series series) async {
    final dir = await _seriesDir();
    final file = File(p.join(dir.path, 'series-${series.id}.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(series.toJson()));
  }
}
