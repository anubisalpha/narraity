import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../models/timeline.dart';
import '../state/manuscript_provider.dart';
import '../state/reference_provider.dart';
import '../state/timeline_provider.dart';

/// In-story chronology: parallel tracks of events, each optionally linked to
/// scenes, characters, and world entries (PLAN.md "Feature: Timeline Page").
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
            : _TrackList(project: project, tracks: tracks, events: events),
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

class _TrackList extends ConsumerWidget {
  const _TrackList({required this.project, required this.tracks, required this.events});

  final Project project;
  final List<TimelineTrack> tracks;
  final List<TimelineEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hiddenTrackIdsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 8,
            children: [
              for (final track in tracks)
                FilterChip(
                  label: Text(track.name),
                  selected: !hidden.contains(track.id),
                  onSelected: (selected) {
                    final next = {...hidden};
                    selected ? next.remove(track.id) : next.add(track.id);
                    ref.read(hiddenTrackIdsProvider.notifier).state = next;
                  },
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final track in tracks)
                if (!hidden.contains(track.id))
                  _TrackRow(
                    project: project,
                    track: track,
                    events: events.where((e) => e.trackId == track.id).toList(),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrackRow extends ConsumerWidget {
  const _TrackRow({required this.project, required this.track, required this.events});

  final Project project;
  final TimelineTrack track;
  final List<TimelineEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(track.name, style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                IconButton(
                  tooltip: 'New Event',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => _addEvent(context, ref),
                ),
                IconButton(
                  tooltip: 'Delete Track',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _deleteTrack(context, ref),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 132,
            child: events.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('No events on this track yet.',
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  )
                : ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (var i = 0; i < events.length; i++)
                        _EventCard(
                          project: project,
                          event: events[i],
                          canMoveLeft: i > 0,
                          canMoveRight: i < events.length - 1,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
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

class _EventCard extends ConsumerWidget {
  const _EventCard({
    required this.project,
    required this.event,
    required this.canMoveLeft,
    required this.canMoveRight,
  });

  final Project project;
  final TimelineEvent event;
  final bool canMoveLeft;
  final bool canMoveRight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 220,
      child: Card(
        margin: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
        child: InkWell(
          onTap: () => _edit(context, ref),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(event.label,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (event.timeLabel.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(event.timeLabel, style: Theme.of(context).textTheme.labelSmall),
                  ),
                if (event.linkedSceneIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final sceneId in event.linkedSceneIds)
                          _SceneJumpChip(sceneId: sceneId),
                      ],
                    ),
                  ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Move earlier',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      icon: const Icon(Icons.chevron_left),
                      onPressed: canMoveLeft ? () => _move(ref, -1) : null,
                    ),
                    IconButton(
                      tooltip: 'Move later',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      icon: const Icon(Icons.chevron_right),
                      onPressed: canMoveRight ? () => _move(ref, 1) : null,
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

  Future<void> _move(WidgetRef ref, int delta) async {
    final service = await ref.read(timelineServiceProvider(project).future);
    await service.moveEvent(event.id, delta);
    invalidateTimeline(ref, project);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    await showTimelineEventDialog(context, ref, project: project, event: event);
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
