import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/timeline.dart';

const _uuid = Uuid();

/// Reads/writes a project's `timelines/timeline-<id>.json` (tracks) and
/// `timelines/event-<id>.json` (events) — both live in the same directory,
/// distinguished by filename prefix, matching PLAN.md's data model.
class TimelineService {
  TimelineService(this.projectDir);

  final Directory projectDir;

  Directory get _dir => Directory(p.join(projectDir.path, 'timelines'));

  // ---- tracks -----------------------------------------------------------

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
    return tracks;
  }

  Future<TimelineTrack> addTrack(String name) async {
    final track = TimelineTrack(id: 'timeline-${_uuid.v4()}', name: name);
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
    events.sort((a, b) => a.order.compareTo(b.order));
    return events;
  }

  Future<TimelineEvent> addEvent({
    required String trackId,
    required String label,
    String timeLabel = '',
  }) async {
    final siblingCount = (await listEvents()).where((e) => e.trackId == trackId).length;
    final event = TimelineEvent(
      id: 'event-${_uuid.v4()}',
      trackId: trackId,
      label: label,
      timeLabel: timeLabel,
      order: siblingCount,
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

  /// Swaps [id] with its neighbour in track order — same "nudge one step"
  /// contract as the rest of the app's reordering (todos, plot points), just
  /// expressed as delta rather than an index pair since events aren't held
  /// in one in-memory list between calls.
  Future<void> moveEvent(String id, int delta) async {
    final events = await listEvents();
    final event = events.firstWhere((e) => e.id == id);
    final track = events.where((e) => e.trackId == event.trackId).toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    final index = track.indexWhere((e) => e.id == id);
    final target = index + delta;
    if (target < 0 || target >= track.length) return;

    final other = track[target];
    final eventOrder = event.order;
    event.order = other.order;
    other.order = eventOrder;
    await saveEvent(event);
    await saveEvent(other);
  }
}
