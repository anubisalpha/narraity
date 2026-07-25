import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/plot_grid.dart';
import '../models/project.dart';
import '../state/plot_grid_provider.dart';

const _plotlineColumnWidth = 180.0;
const _sceneColumnWidth = 160.0;
const _rowHeight = 72.0;

/// Preset palette for new plotlines — a colour picker is overkill for
/// picking one of "roughly this many visually distinct threads at once".
const _plotlineColors = <Color>[
  Color(0xFF5B8DEF),
  Color(0xFFE0685B),
  Color(0xFF56B87A),
  Color(0xFFD9A441),
  Color(0xFF9B6BD9),
  Color(0xFF3FB3B3),
  Color(0xFFD9679B),
  Color(0xFF8A8F98),
];

/// Plot lines (rows) crossed with manuscript scenes (columns, in manuscript
/// order); each intersection can hold a plot point. Scrolls both ways —
/// scenes across, plotlines down — since either axis can grow past a screen.
class PlotGridScreen extends ConsumerWidget {
  const PlotGridScreen({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plotlinesAsync = ref.watch(plotlineListProvider(project));
    final pointsAsync = ref.watch(plotPointListProvider(project));
    final columnsAsync = ref.watch(sceneColumnsProvider(project));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plot Grid'),
        actions: [
          IconButton(
            tooltip: 'New Plotline',
            icon: const Icon(Icons.add),
            onPressed: () => _addPlotline(context, ref),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: switch ((plotlinesAsync, pointsAsync, columnsAsync)) {
        (AsyncError(:final error), _, _) ||
        (_, AsyncError(:final error), _) ||
        (_, _, AsyncError(:final error)) =>
          Center(child: Text('Failed to load plot grid: $error')),
        (AsyncData(value: final plotlines), AsyncData(value: final points),
              AsyncData(value: final columns)) =>
          plotlines.isEmpty
              ? _EmptyState(onAddPlotline: () => _addPlotline(context, ref))
              : columns.isEmpty
                  ? const Center(
                      child: Text('Add scenes to the manuscript to plot points against them.'),
                    )
                  : _Grid(
                      project: project,
                      plotlines: plotlines,
                      points: points,
                      columns: columns,
                    ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> _addPlotline(BuildContext context, WidgetRef ref) async {
    final result = await _showPlotlineDialog(context);
    if (result == null) return;
    final service = await ref.read(plotGridServiceProvider(project).future);
    await service.addPlotline(result.$1, result.$2.toARGB32());
    invalidatePlotGrid(ref, project);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddPlotline});

  final VoidCallback onAddPlotline;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timeline, size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('No plotlines yet', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Add a plotline to start tracking beats against your scenes.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAddPlotline,
            icon: const Icon(Icons.add),
            label: const Text('New Plotline'),
          ),
        ],
      ),
    );
  }
}

class _Grid extends ConsumerWidget {
  const _Grid({
    required this.project,
    required this.plotlines,
    required this.points,
    required this.columns,
  });

  final Project project;
  final List<PlotLine> plotlines;
  final List<PlotPoint> points;
  final List<(String id, String title)> columns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columnWidths = <int, TableColumnWidth>{
      0: const FixedColumnWidth(_plotlineColumnWidth),
      for (var i = 0; i < columns.length; i++)
        i + 1: const FixedColumnWidth(_sceneColumnWidth),
    };

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Scrollbar(
          notificationPredicate: (n) => n.depth == 1,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              columnWidths: columnWidths,
              border: TableBorder.all(color: Theme.of(context).dividerColor),
              defaultVerticalAlignment: TableCellVerticalAlignment.fill,
              children: [
                TableRow(
                  decoration:
                      BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh),
                  children: [
                    const _HeaderCell(label: ''),
                    for (final column in columns) _HeaderCell(label: column.$2),
                  ],
                ),
                for (final plotline in plotlines)
                  TableRow(
                    children: [
                      _PlotlineCell(
                        project: project,
                        plotline: plotline,
                      ),
                      for (final column in columns)
                        _PointCell(
                          project: project,
                          plotline: plotline,
                          sceneId: column.$1,
                          point: points.firstWhereOrNull(
                              (pt) => pt.plotlineId == plotline.id && pt.sceneId == column.$1),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge),
        ),
      ),
    );
  }
}

class _PlotlineCell extends ConsumerWidget {
  const _PlotlineCell({required this.project, required this.plotline});

  final Project project;
  final PlotLine plotline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: _rowHeight,
      child: InkWell(
        onTap: () => _edit(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: Color(plotline.color), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(plotline.name,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: 'Delete Plotline',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final result = await _showPlotlineDialog(context,
        initialName: plotline.name, initialColor: Color(plotline.color));
    if (result == null) return;
    final service = await ref.read(plotGridServiceProvider(project).future);
    await service.updatePlotline(
        plotline.copyWith(name: result.$1, color: result.$2.toARGB32()));
    if (context.mounted) invalidatePlotGrid(ref, project);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Plotline?'),
        content: Text('This removes "${plotline.name}" and every plot point on it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    final service = await ref.read(plotGridServiceProvider(project).future);
    await service.deletePlotline(plotline.id);
    if (context.mounted) invalidatePlotGrid(ref, project);
  }
}

class _PointCell extends ConsumerWidget {
  const _PointCell({
    required this.project,
    required this.plotline,
    required this.sceneId,
    required this.point,
  });

  final Project project;
  final PlotLine plotline;
  final String sceneId;
  final PlotPoint? point;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: _rowHeight,
      child: InkWell(
        onTap: () => _edit(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: point == null
              ? Center(
                  child: Icon(Icons.add,
                      size: 16, color: Theme.of(context).colorScheme.outlineVariant),
                )
              : Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Color(plotline.color).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Color(plotline.color).withValues(alpha: 0.5)),
                  ),
                  child: Text(point!.title,
                      maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final result = await _showPlotPointDialog(context,
        initialTitle: point?.title ?? '', initialNotes: point?.notes ?? '');
    if (result == null) return;
    final service = await ref.read(plotGridServiceProvider(project).future);

    if (result == _deletePlotPoint) {
      if (point != null) await service.deletePlotPoint(point!.id);
    } else {
      await service.setPlotPoint(
        plotlineId: plotline.id,
        sceneId: sceneId,
        title: result.$1,
        notes: result.$2,
      );
    }
    if (context.mounted) invalidatePlotGrid(ref, project);
  }
}

/// Sentinel returned by the plot point dialog's Delete action, distinct from
/// "user cancelled" (null) and "user saved" (a real title/notes pair) — the
/// Save button is disabled whenever the title is empty, so this pair can
/// never arise from a genuine save.
const _deletePlotPoint = ('', '');

Future<(String, Color)?> _showPlotlineDialog(
  BuildContext context, {
  String initialName = '',
  Color initialColor = const Color(0xFF5B8DEF),
}) {
  final controller = TextEditingController(text: initialName);
  var selected = initialColor;
  return showDialog<(String, Color)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(initialName.isEmpty ? 'New Plotline' : 'Edit Plotline'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in _plotlineColors)
                  InkWell(
                    onTap: () => setState(() => selected = color),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: selected == color
                            ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: controller.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, (controller.text.trim(), selected)),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<(String, String)?> _showPlotPointDialog(
  BuildContext context, {
  required String initialTitle,
  required String initialNotes,
}) {
  final titleController = TextEditingController(text: initialTitle);
  final notesController = TextEditingController(text: initialNotes);
  final isEditing = initialTitle.isNotEmpty;
  return showDialog<(String, String)>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(isEditing ? 'Edit Plot Point' : 'New Plot Point'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: titleController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notesController,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
        ],
      ),
      actions: [
        if (isEditing)
          TextButton(
            onPressed: () => Navigator.pop(context, _deletePlotPoint),
            child: const Text('Delete'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: titleController.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context, (titleController.text.trim(), notesController.text.trim())),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
