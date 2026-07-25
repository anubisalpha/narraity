import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../models/timeline.dart';
import '../state/manuscript_provider.dart';
import '../state/reference_provider.dart';
import '../state/timeline_provider.dart';
import '../widgets/immediate_drag_recognizer.dart';

const _cardWidth = 200.0;
const _cardHeight = 100.0;

/// Vertical space given to each track's row — a card centred on the row's
/// baseline (yOffset 0) sits in the middle of this band, with room either
/// side to stagger without normally overlapping the next track.
const _rowHeight = 220.0;
const _topPadding = 60.0;
const _minCanvasWidth = 2400.0;
const _rightMargin = 400.0;

/// In-story chronology: parallel tracks of events, each optionally linked to
/// scenes, characters, and world entries (PLAN.md "Feature: Timeline Page").
/// Tracks are rows on a shared freeform canvas — not a rendered grid/table —
/// so an event's horizontal position (time) and its vertical offset from its
/// own track's baseline (for staggering events that are close together in
/// time) are both freely draggable, the same way Relationship Diagram nodes
/// are. A thin baseline line per track is the only "row" visual; nothing is
/// boxed into cells.
class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(timelineTrackListProvider(project));
    final eventsAsync = ref.watch(timelineEventListProvider(project));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timeline'),
        actions: [
          IconButton(
            tooltip: 'New Track',
            icon: const Icon(Icons.add),
            onPressed: () => _addTrack(context, ref),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: switch ((tracksAsync, eventsAsync)) {
        (AsyncError(:final error), _) || (_, AsyncError(:final error)) =>
          Center(child: Text('Failed to load timeline: $error')),
        (AsyncData(value: final tracks), AsyncData(value: final events)) => tracks.isEmpty
            ? _EmptyState(onAddTrack: () => _addTrack(context, ref))
            : Row(
                children: [
                  Expanded(
                    child: _TimelineCanvas(project: project, tracks: tracks, events: events),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 260,
                    child: _TrackSidebar(project: project, tracks: tracks),
                  ),
                ],
              ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> _addTrack(BuildContext context, WidgetRef ref) async {
    final name = await _promptText(context, title: 'New Track', label: 'Track name');
    if (name == null || name.trim().isEmpty) return;
    final service = await ref.read(timelineServiceProvider(project).future);
    await service.addTrack(name.trim());
    invalidateTimeline(ref, project);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddTrack});

  final VoidCallback onAddTrack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.route, size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('No tracks yet', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Add a track (e.g. "Main" or a POV character) to place events on.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAddTrack,
            icon: const Icon(Icons.add),
            label: const Text('New Track'),
          ),
        ],
      ),
    );
  }
}

/// Track management — reordering (row position on the canvas), visibility,
/// per-track "add event", and delete. Kept as a side list rather than
/// controls scattered across the canvas, the same way the Relationship
/// Diagram keeps relationship management in a side list instead of on the
/// canvas itself.
class _TrackSidebar extends ConsumerWidget {
  const _TrackSidebar({required this.project, required this.tracks});

  final Project project;
  final List<TimelineTrack> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hiddenTrackIdsProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (var i = 0; i < tracks.length; i++)
          _TrackSidebarRow(
            project: project,
            track: tracks[i],
            visible: !hidden.contains(tracks[i].id),
            canMoveUp: i > 0,
            canMoveDown: i < tracks.length - 1,
          ),
      ],
    );
  }
}

class _TrackSidebarRow extends ConsumerWidget {
  const _TrackSidebarRow({
    required this.project,
    required this.track,
    required this.visible,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  final Project project;
  final TimelineTrack track;
  final bool visible;
  final bool canMoveUp;
  final bool canMoveDown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: visible ? 'Hide track' : 'Show track',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: Icon(visible ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () {
                  final hidden = ref.read(hiddenTrackIdsProvider);
                  final next = {...hidden};
                  visible ? next.add(track.id) : next.remove(track.id);
                  ref.read(hiddenTrackIdsProvider.notifier).state = next;
                },
              ),
              Expanded(
                child: Text(track.name,
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Move up',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: const Icon(Icons.arrow_upward),
                onPressed: canMoveUp ? () => _moveTrack(ref, -1) : null,
              ),
              IconButton(
                tooltip: 'Move down',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: const Icon(Icons.arrow_downward),
                onPressed: canMoveDown ? () => _moveTrack(ref, 1) : null,
              ),
              IconButton(
                tooltip: 'New Event',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: const Icon(Icons.add),
                onPressed: () => _addEvent(context, ref),
              ),
              IconButton(
                tooltip: 'Delete Track',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteTrack(context, ref),
              ),
            ],
          ),
          const Divider(height: 8),
        ],
      ),
    );
  }

  Future<void> _moveTrack(WidgetRef ref, int delta) async {
    final service = await ref.read(timelineServiceProvider(project).future);
    await service.moveTrack(track.id, delta);
    invalidateTimeline(ref, project);
  }

  Future<void> _addEvent(BuildContext context, WidgetRef ref) async {
    final label = await _promptText(context, title: 'New Event', label: 'Event label');
    if (label == null || label.trim().isEmpty) return;
    final service = await ref.read(timelineServiceProvider(project).future);
    await service.addEvent(trackId: track.id, label: label.trim());
    if (context.mounted) invalidateTimeline(ref, project);
  }

  Future<void> _deleteTrack(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Track?'),
        content: Text('This removes "${track.name}" and every event on it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    final service = await ref.read(timelineServiceProvider(project).future);
    await service.deleteTrack(track.id);
    if (context.mounted) invalidateTimeline(ref, project);
  }
}

class _TimelineCanvas extends ConsumerStatefulWidget {
  const _TimelineCanvas({required this.project, required this.tracks, required this.events});

  final Project project;
  final List<TimelineTrack> tracks;
  final List<TimelineEvent> events;

  @override
  ConsumerState<_TimelineCanvas> createState() => _TimelineCanvasState();
}

class _TimelineCanvasState extends ConsumerState<_TimelineCanvas> {
  /// The canvas Stack's own render box — event cards are `Positioned`
  /// relative to this, so converting a raw (global, screen-space) pointer
  /// position into this coordinate space is what lets a drag track the
  /// cursor exactly at any pan/zoom level (see `ImmediateDragRecognizer`'s
  /// doc comment for the bug this avoids).
  final _stackKey = GlobalKey();

  Offset _globalToLocal(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global) ?? global;
  }

  @override
  Widget build(BuildContext context) {
    final hidden = ref.watch(hiddenTrackIdsProvider);
    final visibleTracks = [
      for (final track in widget.tracks) if (!hidden.contains(track.id)) track,
    ];
    final baselineY = {
      for (var i = 0; i < visibleTracks.length; i++)
        visibleTracks[i].id: _topPadding + i * _rowHeight + _rowHeight / 2,
    };
    final visibleEvents = [
      for (final event in widget.events) if (baselineY.containsKey(event.trackId)) event,
    ];

    final maxEventX =
        visibleEvents.fold(_minCanvasWidth - _rightMargin, (max, e) => e.x > max ? e.x : max);
    final canvasWidth = maxEventX + _rightMargin;
    final canvasHeight = _topPadding * 2 + visibleTracks.length * _rowHeight;

    return InteractiveViewer(
      constrained: false,
      minScale: 0.3,
      maxScale: 2,
      boundaryMargin: const EdgeInsets.all(200),
      child: SizedBox(
        width: canvasWidth,
        height: canvasHeight,
        child: Stack(
          key: _stackKey,
          children: [
            for (final track in visibleTracks)
              Positioned(
                left: 0,
                top: baselineY[track.id]!,
                width: canvasWidth,
                child: Container(height: 1, color: Theme.of(context).dividerColor),
              ),
            for (final track in visibleTracks)
              Positioned(
                left: 8,
                top: baselineY[track.id]! - 18,
                child: Text(track.name, style: Theme.of(context).textTheme.labelSmall),
              ),
            for (final event in visibleEvents)
              _EventCard(
                key: ValueKey(event.id),
                project: widget.project,
                event: event,
                trackBaselineY: baselineY[event.trackId]!,
                globalToLocal: _globalToLocal,
              ),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends ConsumerStatefulWidget {
  const _EventCard({
    super.key,
    required this.project,
    required this.event,
    required this.trackBaselineY,
    required this.globalToLocal,
  });

  final Project project;
  final TimelineEvent event;

  /// This event's own track's row centre — its rendered position is this
  /// plus the event's `yOffset` (the stagger), never another track's.
  final double trackBaselineY;

  final Offset Function(Offset global) globalToLocal;

  @override
  ConsumerState<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends ConsumerState<_EventCard> {
  Offset? _dragTopLeft;

  /// Local-space offset from the card's top-left to wherever the user
  /// actually grabbed it — see ImmediateDragRecognizer's doc comment: this
  /// is what makes the drag track the cursor exactly instead of lagging.
  Offset? _grabOffset;

  Offset get _restingTopLeft =>
      Offset(widget.event.x, widget.trackBaselineY + widget.event.yOffset - _cardHeight / 2);

  @override
  Widget build(BuildContext context) {
    final topLeft = _dragTopLeft ?? _restingTopLeft;

    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      child: RawGestureDetector(
        gestures: {
          ImmediateDragRecognizer:
              GestureRecognizerFactoryWithHandlers<ImmediateDragRecognizer>(
            ImmediateDragRecognizer.new,
            (recognizer) {
              recognizer.onDown = (globalPosition) {
                _grabOffset = widget.globalToLocal(globalPosition) - topLeft;
              };
              recognizer.onMove = (globalPosition) {
                final grabOffset = _grabOffset;
                if (grabOffset == null) return;
                setState(() => _dragTopLeft = widget.globalToLocal(globalPosition) - grabOffset);
              };
              recognizer.onEnd = () => _handleDragEnd();
            },
          ),
        },
        child: SizedBox(
          width: _cardWidth,
          height: _cardHeight,
          child: Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              onTap: () => showTimelineEventDialog(context, ref, project: widget.project, event: widget.event),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.event.label,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    if (widget.event.timeLabel.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(widget.event.timeLabel,
                            style: Theme.of(context).textTheme.labelSmall),
                      ),
                    if (widget.event.linkedSceneIds.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final sceneId in widget.event.linkedSceneIds)
                              _SceneJumpChip(sceneId: sceneId),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleDragEnd() async {
    final topLeft = _dragTopLeft;
    if (topLeft == null) return;
    final x = topLeft.dx;
    final yOffset = topLeft.dy - (widget.trackBaselineY - _cardHeight / 2);
    final service = await ref.read(timelineServiceProvider(widget.project).future);
    await service.setEventPosition(widget.event, x, yOffset);
    if (mounted) invalidateTimeline(ref, widget.project);
  }
}

/// A linked scene rendered as a chip; tapping it leaves the Timeline and
/// jumps straight to that scene in the manuscript editor.
class _SceneJumpChip extends ConsumerWidget {
  const _SceneJumpChip({required this.sceneId});

  final String sceneId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ActionChip(
      visualDensity: VisualDensity.compact,
      avatar: const Icon(Icons.menu_book_outlined, size: 14),
      label: const Text('Open scene', style: TextStyle(fontSize: 11)),
      onPressed: () {
        Navigator.of(context).pop();
        openScene(ref, sceneId);
      },
    );
  }
}

Future<String?> _promptText(BuildContext context, {required String title, required String label}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
      ],
    ),
  );
}

/// Full event editor: label, time label, notes, and multi-select links to
/// scenes/characters/world entries. Exposed as a top-level function (rather
/// than a private dialog builder) so both the event card and, later, other
/// entry points (e.g. a character's own timeline view) can open it the same
/// way.
Future<void> showTimelineEventDialog(
  BuildContext context,
  WidgetRef ref, {
  required Project project,
  required TimelineEvent event,
}) async {
  final labelController = TextEditingController(text: event.label);
  final timeController = TextEditingController(text: event.timeLabel);
  final notesController = TextEditingController(text: event.notes);
  var linkedScenes = {...event.linkedSceneIds};
  var linkedCharacters = {...event.linkedCharacterIds};
  var linkedWorld = {...event.linkedWorldIds};

  final scenes = await ref.read(sceneColumnsProvider(project).future);
  final characters = await ref.read(characterListProvider(project).future);
  final world = await ref.read(worldListProvider(project).future);
  if (!context.mounted) return;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Edit Event'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: timeController,
                  decoration:
                      const InputDecoration(labelText: 'When (e.g. "Day 3", "Spring, Year 1")'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 16),
                _LinkSection(
                  title: 'Scenes',
                  options: [for (final s in scenes) (s.$1, s.$2)],
                  selected: linkedScenes,
                  onChanged: (id, value) => setState(
                      () => value ? linkedScenes.add(id) : linkedScenes.remove(id)),
                ),
                _LinkSection(
                  title: 'Characters',
                  options: [for (final c in characters) (c.id, c.name)],
                  selected: linkedCharacters,
                  onChanged: (id, value) => setState(
                      () => value ? linkedCharacters.add(id) : linkedCharacters.remove(id)),
                ),
                _LinkSection(
                  title: 'World',
                  options: [for (final w in world) (w.id, w.name)],
                  selected: linkedWorld,
                  onChanged: (id, value) =>
                      setState(() => value ? linkedWorld.add(id) : linkedWorld.remove(id)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final service = await ref.read(timelineServiceProvider(project).future);
              await service.deleteEvent(event.id);
              if (context.mounted) Navigator.pop(context, false);
            },
            child: const Text('Delete'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: labelController.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );

  if (result != true) {
    if (result == false) invalidateTimeline(ref, project); // deleted
    return;
  }

  final service = await ref.read(timelineServiceProvider(project).future);
  await service.saveEvent(event.copyWith(
    label: labelController.text.trim(),
    timeLabel: timeController.text.trim(),
    notes: notesController.text.trim(),
    linkedSceneIds: linkedScenes.toList(),
    linkedCharacterIds: linkedCharacters.toList(),
    linkedWorldIds: linkedWorld.toList(),
  ));
  invalidateTimeline(ref, project);
}

class _LinkSection extends StatelessWidget {
  const _LinkSection({
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final List<(String id, String label)> options;
  final Set<String> selected;
  final void Function(String id, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in options)
                FilterChip(
                  label: Text(option.$2),
                  selected: selected.contains(option.$1),
                  onSelected: (value) => onChanged(option.$1, value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
