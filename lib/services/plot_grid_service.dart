import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/plot_grid.dart';

const _uuid = Uuid();

/// Reads/writes a project's `plot-grid/plotlines.json` and
/// `plot-grid/plotpoints.json`.
class PlotGridService {
  PlotGridService(this.projectDir);

  final Directory projectDir;

  Directory get _gridDir => Directory(p.join(projectDir.path, 'plot-grid'));
  File get _plotlinesFile => File(p.join(_gridDir.path, 'plotlines.json'));
  File get _plotpointsFile => File(p.join(_gridDir.path, 'plotpoints.json'));

  // ---- plotlines ------------------------------------------------------------

  Future<List<PlotLine>> listPlotlines() async {
    if (!await _plotlinesFile.exists()) return [];
    try {
      final json = jsonDecode(await _plotlinesFile.readAsString()) as Map<String, dynamic>;
      return (json['plotlines'] as List<dynamic>? ?? [])
          .map((l) => PlotLine.fromJson(l as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<PlotLine> addPlotline(String name, int color) async {
    final plotlines = await listPlotlines();
    final plotline = PlotLine(id: 'plotline-${_uuid.v4()}', name: name, color: color);
    plotlines.add(plotline);
    await _savePlotlines(plotlines);
    return plotline;
  }

  Future<void> updatePlotline(PlotLine updated) async {
    final plotlines = await listPlotlines();
    final index = plotlines.indexWhere((l) => l.id == updated.id);
    if (index == -1) return;
    plotlines[index] = updated;
    await _savePlotlines(plotlines);
  }

  /// Removes the plotline and every plot point on it — an orphaned point
  /// (row deleted, cell left behind) would just be dead data nobody can see.
  Future<void> deletePlotline(String id) async {
    final plotlines = await listPlotlines();
    plotlines.removeWhere((l) => l.id == id);
    await _savePlotlines(plotlines);

    final points = await listPlotPoints();
    points.removeWhere((pt) => pt.plotlineId == id);
    await _savePlotPoints(points);
  }

  /// Matches `ReorderableListView.onReorder`'s index convention (newIndex is
  /// post-removal) — same contract as `ManuscriptService.reorderNode`.
  Future<void> reorderPlotline(int oldIndex, int newIndex) async {
    final plotlines = await listPlotlines();
    final line = plotlines.removeAt(oldIndex);
    plotlines.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, line);
    await _savePlotlines(plotlines);
  }

  Future<void> _savePlotlines(List<PlotLine> plotlines) async {
    await _gridDir.create(recursive: true);
    await _plotlinesFile.writeAsString(const JsonEncoder.withIndent('  ')
        .convert({'plotlines': plotlines.map((l) => l.toJson()).toList()}));
  }

  // ---- plot points ------------------------------------------------------------

  Future<List<PlotPoint>> listPlotPoints() async {
    if (!await _plotpointsFile.exists()) return [];
    try {
      final json = jsonDecode(await _plotpointsFile.readAsString()) as Map<String, dynamic>;
      return (json['plotpoints'] as List<dynamic>? ?? [])
          .map((pt) => PlotPoint.fromJson(pt as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// One point per plotline/scene cell — adding to an already-filled cell
  /// overwrites it rather than stacking a second card nobody can see behind
  /// the first.
  Future<PlotPoint> setPlotPoint({
    required String plotlineId,
    required String sceneId,
    required String title,
    String notes = '',
  }) async {
    final points = await listPlotPoints();
    final index =
        points.indexWhere((pt) => pt.plotlineId == plotlineId && pt.sceneId == sceneId);
    final point = PlotPoint(
      id: index == -1 ? 'plotpoint-${_uuid.v4()}' : points[index].id,
      plotlineId: plotlineId,
      sceneId: sceneId,
      title: title,
      notes: notes,
    );
    if (index == -1) {
      points.add(point);
    } else {
      points[index] = point;
    }
    await _savePlotPoints(points);
    return point;
  }

  Future<void> deletePlotPoint(String id) async {
    final points = await listPlotPoints();
    points.removeWhere((pt) => pt.id == id);
    await _savePlotPoints(points);
  }

  Future<void> _savePlotPoints(List<PlotPoint> points) async {
    await _gridDir.create(recursive: true);
    await _plotpointsFile.writeAsString(const JsonEncoder.withIndent('  ')
        .convert({'plotpoints': points.map((pt) => pt.toJson()).toList()}));
  }
}
