import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/library_service.dart';
import 'package:narraity/services/series_service.dart';

void main() {
  late Directory tempDir;
  late LibraryService library;
  late SeriesService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_series_test_');
    library = LibraryService(rootOverride: tempDir);
    service = SeriesService(library);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('a new library has no series', () async {
    expect(await service.listSeries(), isEmpty);
  });

  test('createSeries writes a file under _Series/, which listProjects ignores as a project',
      () async {
    final series = await service.createSeries(title: 'Wisdom of the Elders');

    expect(series.title, 'Wisdom of the Elders');
    expect(await File('${tempDir.path}/_Series/series-${series.id}.json').exists(), isTrue);
    expect(await library.listProjects(), isEmpty);
  });

  test('listSeries finds created series, newest-modified first', () async {
    final a = await service.createSeries(title: 'Older');
    await Future.delayed(const Duration(milliseconds: 5));
    final b = await service.createSeries(title: 'Newer');

    final series = await service.listSeries();
    expect(series.map((s) => s.id), [b.id, a.id]);
  });

  test('renameSeries persists the new title and bumps modified', () async {
    final series = await service.createSeries(title: 'Draft Title');
    await Future.delayed(const Duration(milliseconds: 5));
    await service.renameSeries(series, 'Final Title');

    final reloaded = await service.listSeries();
    expect(reloaded.single.title, 'Final Title');
    expect(reloaded.single.modified.isAfter(series.modified), isTrue);
  });

  test('deleteSeries removes the series but leaves member projects\' seriesId dangling, '
      'not deleted', () async {
    final series = await service.createSeries(title: 'A Series');
    final project = await library.createProject(title: 'Book One', seriesId: series.id);

    await service.deleteSeries(series);

    expect(await service.listSeries(), isEmpty);
    final reloadedProjects = await library.listProjects();
    expect(reloadedProjects.single.id, project.id);
    expect(reloadedProjects.single.seriesId, series.id); // untouched — library UI treats it as standalone
  });

  test('sortOrder round-trips via saveSeries, including 0 (a valid position, not "unset")',
      () async {
    final series = await service.createSeries(title: 'A Series');
    expect(series.sortOrder, isNull);

    await service.saveSeries(series.copyWith(sortOrder: 0));
    final reloaded = await service.listSeries();
    expect(reloaded.single.sortOrder, 0);
  });
}
