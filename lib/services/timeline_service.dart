import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/timeline.dart';

const _uuid = Uuid();

/// Horizontal gap given to a newly-added event, placed after whatever's
/// currently rightmost on its track — keeps new events from landing on top
/// of existing ones.
const _newEventGap = 200.0;

/// Reads/writes a project's `timelines/timeline-<id>.json` (tracks) and
/// `timelines/event-<id>.json` (events) — both live in the same directory,
/// distinguished by filename prefix, matching PLAN.md's data model.
class TimelineService {
  TimelineService(this.projectDir);

  final Directory projectDir;

  Directory get _dir => Directory(p.join(projectDir.path, 'timelines'));

  // ---- tracks -----------------------------------------------------------

  /// Sorted by [TimelineTrack.order] (row position), with id as a tiebreaker
  /// for determinism when two tracks share an order (e.g. every track
  /// created before track ordering existed, all defaulting to 0).
  Future<List<TimelineTrack>> listTracks() async {
    if (!await _dir.exists()) return [];
    final tracks = <TimelineTrack>[];
    await for (final entity in _dir.list()) {
      if (entity is! File || !p.basename(entity.path).startsWith('timeline-')) continue;
      try {
        final json = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        tracks.add(TimelineTrack.fromJson(json));
      } catch (_) {
        continue; // skip a corrupt file rather than failing the whole screen
      }
    }
    tracks.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
    });
    return tracks;
  }

  Future<TimelineTrack> addTrack(String name) async {
    final order = (await listTracks()).length;
    final track = TimelineTrack(id: 'timeline-${_uuid.v4()}', name: name, order: order);
    await saveTrack(track);
    return track;
  }

  Future<void> saveTrack(TimelineTrack track) async {
    await _dir.create(recursive: true);
    await File(p.join(_dir.path, '${track.id}.json'))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(track.toJson()));
  }

  /// Deletes the track and every event on it — an orphaned event with no
  /// track to render under would just be invisible dead data.
  Future<void> deleteTrack(String id) async {
    final file = File(p.join(_dir.path, '$id.json'));
    if (await file.exists()) await file.delete();

    for (final event in await listEvents()) {
      if (event.trackId == id) await deleteEvent(event.id);
    }
  }

  /// Swaps [id] with its neighbour in row order — same "nudge one step"
  /// contract used throughout the app's other reordering (todos, plot
  /// points, plotlines).
  ///
  /// Re-sequences every track to distinct, contiguous values first: tracks
  /// created before track ordering existed (or otherwise sharing an `order`
  /// value, e.g. all defaulting to 0) would make a same-value swap a no-op —
  /// this was a real bug, the up/down buttons visibly did nothing for a
  /// project with pre-existing tracks. Re-sequencing is self-healing and
  /// only needs to happen once; afterwards every track has its own value.
  Future<void> moveTrack(String id, int delta) async {
    final tracks = await listTracks();
    final index = tracks.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final target = index + delta;
    if (target < 0 || target >= tracks.length) return;

    for (var i = 0; i < tracks.length; i++) {
      tracks[i].order = i;
    }
    final track = tracks[index];
    final other = tracks[target];
    final trackOrder = track.order;
    track.order = other.order;
    other.order = trackOrder;

    for (final t in tracks) {
      await saveTrack(t);
    }
  }

  // ---- events -------------------------------------------------------------

  Future<List<TimelineEvent>> listEvents() async {
    if (!await _dir.exists()) return [];
    final events = <TimelineEvent>[];
    await for (final entity in _dir.list()) {
      if (entity is! File || !p.basename(entity.path).startsWith('event-')) continue;
      try {
        final json = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        events.add(TimelineEvent.fromJson(json));
      } catch (_) {
        continue;
      }
    }
    events.sort((a, b) => a.x.compareTo(b.x));
    return events;
  }

  /// New events land to the right of whatever's already on the track
  /// (freeform position, but appending reads naturally left-to-right), at
  /// the track's own baseline (no stagger) until dragged.
  Future<TimelineEvent> addEvent({
    required String trackId,
    required String label,
    String timeLabel = '',
  }) async {
    final onTrack = (await listEvents()).where((e) => e.trackId == trackId);
    final rightmostX = onTrack.isEmpty ? 40.0 - _newEventGap : onTrack.map((e) => e.x).reduce(
        (a, b) => a > b ? a : b);
    final event = TimelineEvent(
      id: 'event-${_uuid.v4()}',
      trackId: trackId,
      label: label,
      timeLabel: timeLabel,
      x: rightmostX + _newEventGap,
    );
    await saveEvent(event);
    return event;
  }

  Future<void> saveEvent(TimelineEvent event) async {
    await _dir.create(recursive: true);
    await File(p.join(_dir.path, '${event.id}.json'))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(event.toJson()));
  }

  Future<void> deleteEvent(String id) async {
    final file = File(p.join(_dir.path, '$id.json'));
    if (await file.exists()) await file.delete();
  }

  /// Persists a freeform drag — the event's horizontal position, its
  /// stagger offset from the track's baseline, and (if the drag landed
  /// closer to a different track's baseline than its own) a reassignment to
  /// that track, all in one write.
  Future<void> setEventPosition(
    TimelineEvent event,
    double x,
    double yOffset, {
    String? trackId,
  }) async {
    await saveEvent(event.copyWith(x: x, yOffset: yOffset, trackId: trackId));
  }
}
