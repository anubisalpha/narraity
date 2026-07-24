import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/project.dart';
import '../models/scene_snapshot.dart';
import '../state/scene_history_provider.dart';

/// Per-scene History view: timeline, word-count sparkline, diff between any
/// two points, one-click restore (PLAN.md "Version History" UI).
class SceneHistoryScreen extends ConsumerStatefulWidget {
  const SceneHistoryScreen({
    super.key,
    required this.project,
    required this.sceneId,
    required this.sceneTitle,
    required this.onRestored,
  });

  final Project project;
  final String sceneId;
  final String sceneTitle;

  /// Called with the restored text once the user confirms a restore, so the
  /// caller (the open editor) can load it without this screen needing to
  /// know about the editor's controller.
  final void Function(String restoredContent) onRestored;

  @override
  ConsumerState<SceneHistoryScreen> createState() => _SceneHistoryScreenState();
}

class _SceneHistoryScreenState extends ConsumerState<SceneHistoryScreen> {
  /// The two snapshots selected for comparison — tap one, then another.
  SceneSnapshot? _compareA;
  SceneSnapshot? _compareB;

  Future<void> _saveCheckpoint() async {
    final labelController = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Checkpoint'),
        content: TextField(
          controller: labelController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Label',
            hintText: 'e.g. "First draft complete"',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(labelController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (label == null || label.trim().isEmpty) return;

    final service = await ref.read(sceneHistoryServiceProvider(widget.project).future);
    final current = await service.reconstructContent(widget.sceneId);
    await service.recordCheckpoint(widget.sceneId, current, label.trim());
    ref.invalidate(sceneSnapshotsProvider((widget.project, widget.sceneId)));
  }

  Future<void> _restore(SceneSnapshot snapshot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this version?'),
        content: Text(
          'The scene will be set back to how it was at '
          '${DateFormat.yMMMd().add_jm().format(snapshot.timestamp)}. '
          'This is itself recorded as a new history entry, so nothing is lost — '
          'you can undo the restore later from here too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final service = await ref.read(sceneHistoryServiceProvider(widget.project).future);
    final restored = await service.restore(widget.sceneId, snapshot.id);
    ref.invalidate(sceneSnapshotsProvider((widget.project, widget.sceneId)));
    widget.onRestored(restored);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Restored — see the editor')));
    }
  }

  void _tapForCompare(SceneSnapshot snapshot) {
    setState(() {
      if (_compareA == null || (_compareA != null && _compareB != null)) {
        _compareA = snapshot;
        _compareB = null;
      } else if (snapshot.id != _compareA!.id) {
        _compareB = snapshot;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshotsAsync =
        ref.watch(sceneSnapshotsProvider((widget.project, widget.sceneId)));

    return Scaffold(
      appBar: AppBar(
        title: Text('History — ${widget.sceneTitle}'),
        actions: [
          TextButton.icon(
            onPressed: _saveCheckpoint,
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Save Checkpoint'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: snapshotsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Failed to load history: $err')),
        data: (snapshots) {
          if (snapshots.isEmpty) {
            return const Center(
              child: Text('No history yet — keep writing and snapshots will appear here.'),
            );
          }

          return Row(
            children: [
              SizedBox(
                width: 340,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: _WordCountSparkline(snapshots: snapshots),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        _compareA == null
                            ? 'Tap a snapshot to see what changed'
                            : _compareB == null
                                ? 'Tap another to compare, or Restore/view diff below'
                                : 'Comparing two selected snapshots',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: snapshots.length,
                        itemBuilder: (context, index) {
                          // Newest first.
                          final snapshot = snapshots[snapshots.length - 1 - index];
                          final selected =
                              snapshot.id == _compareA?.id || snapshot.id == _compareB?.id;
                          return ListTile(
                            selected: selected,
                            leading: Icon(
                              snapshot.type == SnapshotType.checkpoint
                                  ? Icons.flag
                                  : Icons.history,
                              color: snapshot.type == SnapshotType.checkpoint
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            title: Text(
                              snapshot.label ?? DateFormat.yMMMd().add_jm().format(snapshot.timestamp),
                            ),
                            subtitle: Text(
                              '${snapshot.wordCount} words'
                              '${snapshot.label != null ? ' · ${DateFormat.yMMMd().add_jm().format(snapshot.timestamp)}' : ''}',
                            ),
                            trailing: IconButton(
                              tooltip: 'Restore this version',
                              icon: const Icon(Icons.restore),
                              onPressed: () => _restore(snapshot),
                            ),
                            onTap: () => _tapForCompare(snapshot),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _DiffPane(
                  project: widget.project,
                  sceneId: widget.sceneId,
                  snapshots: snapshots,
                  compareA: _compareA,
                  compareB: _compareB,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Minimal line chart of word count across snapshots — a lightweight
/// stand-in for a fuller chart, consistent with the sparkline approach
/// already used for the goals heatmap.
class _WordCountSparkline extends StatelessWidget {
  const _WordCountSparkline({required this.snapshots});

  final List<SceneSnapshot> snapshots;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: snapshots.map((s) => s.wordCount).toList(),
          color: Theme.of(context).colorScheme.primary,
        ),
          size: Size.infinite,
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxValue = values.reduce((a, b) => a > b ? a : b).toDouble();
    final minValue = values.reduce((a, b) => a < b ? a : b).toDouble();
    final range = (maxValue - minValue).clamp(1, double.infinity);

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - ((values[i] - minValue) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values;
}

/// Shows the diff for whatever is selected: nothing selected shows a hint;
/// one selected shows that snapshot's change vs. its immediate predecessor;
/// two selected compares them directly.
class _DiffPane extends ConsumerWidget {
  const _DiffPane({
    required this.project,
    required this.sceneId,
    required this.snapshots,
    required this.compareA,
    required this.compareB,
  });

  final Project project;
  final String sceneId;
  final List<SceneSnapshot> snapshots;
  final SceneSnapshot? compareA;
  final SceneSnapshot? compareB;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (compareA == null) {
      return const Center(child: Text('Select a snapshot to view its diff'));
    }

    final String fromId;
    final String toId;
    if (compareB == null) {
      final index = snapshots.indexWhere((s) => s.id == compareA!.id);
      final predecessor = index > 0 ? snapshots[index - 1] : null;
      fromId = predecessor?.id ?? '';
      toId = compareA!.id;
    } else {
      // Compare chronologically: earlier -> later.
      final ordered = [compareA!, compareB!]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      fromId = ordered.first.id;
      toId = ordered.last.id;
    }

    final serviceAsync = ref.watch(sceneHistoryServiceProvider(project));

    return serviceAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('$err')),
      data: (service) => FutureBuilder<List<String>>(
        future: Future.wait([
          fromId.isEmpty ? Future.value('') : service.reconstructContent(sceneId, upToId: fromId),
          service.reconstructContent(sceneId, upToId: toId),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final from = snapshot.data![0];
          final to = snapshot.data![1];
          final diffs = DiffMatchPatch().diff(from, to);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText.rich(
              TextSpan(
                children: [
                  for (final d in diffs)
                    TextSpan(
                      text: d.text,
                      style: switch (d.operation) {
                        DIFF_INSERT => TextStyle(
                            backgroundColor: Colors.green.withValues(alpha: 0.25),
                          ),
                        DIFF_DELETE => TextStyle(
                            backgroundColor: Colors.red.withValues(alpha: 0.25),
                            decoration: TextDecoration.lineThrough,
                          ),
                        _ => null,
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
