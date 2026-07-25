import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/plot_grid_service.dart';

void main() {
  late Directory tempDir;
  late PlotGridService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_plot_grid_test_');
    service = PlotGridService(tempDir);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('empty project has no plotlines or plot points', () async {
    expect(await service.listPlotlines(), isEmpty);
    expect(await service.listPlotPoints(), isEmpty);
  });

  test('addPlotline persists to plot-grid/plotlines.json and round-trips', () async {
    await service.addPlotline('Main Plot', 0xFF5B8DEF);

    expect(File('${tempDir.path}/plot-grid/plotlines.json').existsSync(), isTrue);
    final plotlines = await service.listPlotlines();
    expect(plotlines.single.name, 'Main Plot');
    expect(plotlines.single.color, 0xFF5B8DEF);
  });

  test('updatePlotline renames and recolors in place', () async {
    final line = await service.addPlotline('Subplot', 0xFF000000);
    await service.updatePlotline(line.copyWith(name: 'Elena Arc', color: 0xFFFFFFFF));

    final reloaded = await service.listPlotlines();
    expect(reloaded.single.name, 'Elena Arc');
    expect(reloaded.single.color, 0xFFFFFFFF);
  });

  test('setPlotPoint creates one point per plotline/scene cell', () async {
    final line = await service.addPlotline('Main Plot', 0xFF5B8DEF);
    await service.setPlotPoint(plotlineId: line.id, sceneId: 'scene-1', title: 'Inciting incident');

    final points = await service.listPlotPoints();
    expect(points.single.title, 'Inciting incident');
    expect(points.single.sceneId, 'scene-1');
  });

  test('setPlotPoint on an already-filled cell overwrites rather than duplicating', () async {
    final line = await service.addPlotline('Main Plot', 0xFF5B8DEF);
    await service.setPlotPoint(plotlineId: line.id, sceneId: 'scene-1', title: 'First draft');
    await service.setPlotPoint(plotlineId: line.id, sceneId: 'scene-1', title: 'Revised beat');

    final points = await service.listPlotPoints();
    expect(points, hasLength(1));
    expect(points.single.title, 'Revised beat');
  });

  test('deletePlotPoint removes only the targeted point', () async {
    final line = await service.addPlotline('Main Plot', 0xFF5B8DEF);
    await service.setPlotPoint(plotlineId: line.id, sceneId: 'scene-1', title: 'Keep me');
    final drop =
        await service.setPlotPoint(plotlineId: line.id, sceneId: 'scene-2', title: 'Delete me');

    await service.deletePlotPoint(drop.id);

    final remaining = await service.listPlotPoints();
    expect(remaining.single.title, 'Keep me');
  });

  test('deletePlotline cascades to drop every point on it, leaves other lines alone', () async {
    final main = await service.addPlotline('Main Plot', 0xFF5B8DEF);
    final sub = await service.addPlotline('Subplot', 0xFFE0685B);
    await service.setPlotPoint(plotlineId: main.id, sceneId: 'scene-1', title: 'Main beat');
    await service.setPlotPoint(plotlineId: sub.id, sceneId: 'scene-1', title: 'Sub beat');

    await service.deletePlotline(main.id);

    final plotlines = await service.listPlotlines();
    expect(plotlines.single.id, sub.id);
    final points = await service.listPlotPoints();
    expect(points.single.plotlineId, sub.id);
  });

  test('reorderPlotline follows ReorderableListView index convention', () async {
    await service.addPlotline('A', 0xFF000000);
    await service.addPlotline('B', 0xFF000000);
    await service.addPlotline('C', 0xFF000000);

    // Move index 0 ("A") to after index 2 -> B, C, A
    await service.reorderPlotline(0, 3);

    final names = (await service.listPlotlines()).map((l) => l.name).toList();
    expect(names, ['B', 'C', 'A']);
  });
}
