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

  Future<Directory> _coversDir() async {
    final root = await _library.libraryRoot();
    return Directory(p.join(root.path, '_Series', 'covers'));
  }

  /// Copies [sourceImage] into `_Series/covers/` as `series-<id>.<ext>`,
  /// replacing any previous cover file (which may have had a different
  /// extension), and persists the new `coverImagePath`. Mirrors
  /// `LibraryService.setCoverImage`'s per-project equivalent, just rooted at
  /// the library root instead of inside a project folder (a series has no
  /// folder of its own).
  Future<Series> setCoverImage(Series series, File sourceImage) async {
    final coversDir = await _coversDir();
    await coversDir.create(recursive: true);

    await for (final entity in coversDir.list()) {
      if (entity is File &&
          p.basenameWithoutExtension(entity.path) == 'series-${series.id}') {
        await entity.delete();
      }
    }

    final ext = p.extension(sourceImage.path);
    final destPath = p.join(coversDir.path, 'series-${series.id}$ext');
    await sourceImage.copy(destPath);

    final updated = series.copyWith(
      coverImagePath: p.join('_Series', 'covers', 'series-${series.id}$ext'),
      modified: DateTime.now(),
    );
    await _write(updated);
    return updated;
  }

  /// Deletes the current cover file (if any) and clears `coverImagePath`.
  Future<Series> removeCoverImage(Series series) async {
    if (series.coverImagePath != null) {
      final root = await _library.libraryRoot();
      final file = File(p.join(root.path, series.coverImagePath!));
      if (await file.exists()) {
        await file.delete();
      }
    }
    final updated = series.copyWith(clearCoverImagePath: true, modified: DateTime.now());
    await _write(updated);
    return updated;
  }

  /// Absolute path to [series]'s cover image file, or null if it has none.
  Future<String?> coverImageAbsolutePath(Series series) async {
    if (series.coverImagePath == null) return null;
    final root = await _library.libraryRoot();
    return p.join(root.path, series.coverImagePath!);
  }
}
