import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/timeline.dart';
import 'package:narraity/services/timeline_service.dart';

void main() {
  late Directory tempDir;
  late TimelineService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_timeline_test_');
    service = TimelineService(tempDir);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('empty project has no tracks or events', () async {
    expect(await service.listTracks(), isEmpty);
    expect(await service.listEvents(), isEmpty);
  });

  test('addTrack persists and round-trips', () async {
    await service.addTrack('Main');

    final tracks = await service.listTracks();
    expect(tracks.single.name, 'Main');
    expect(File('${tempDir.path}/timelines/${tracks.single.id}.json').existsSync(), isTrue);
  });

  test('addEvent places events ascending left-to-right on a track', () async {
    final track = await service.addTrack('Main');
    await service.addEvent(trackId: track.id, label: 'Inciting incident');
    await service.addEvent(trackId: track.id, label: 'Midpoint');

    final events = await service.listEvents();
    expect(events.map((e) => e.label), ['Inciting incident', 'Midpoint']);
    expect(events[0].x, lessThan(events[1].x));
    expect(events.every((e) => e.yOffset == 0), isTrue,
        reason: 'new events sit on the track baseline until dragged');
  });

  test("addEvent's placement is independent per track", () async {
    final trackA = await service.addTrack('Main');
    final trackB = await service.addTrack('Backstory');
    final a1 = await service.addEvent(trackId: trackA.id, label: 'A1');
    final b1 = await service.addEvent(trackId: trackB.id, label: 'B1');

    expect(b1.x, a1.x, reason: 'each track starts its own events from the same default position');
  });

  test('setEventPosition persists a freeform drag (x and yOffset)', () async {
    final track = await service.addTrack('Main');
    final event = await service.addEvent(trackId: track.id, label: 'Reveal');

    await service.setEventPosition(event, 480, -35);

    final reloaded = (await service.listEvents()).single;
    expect(reloaded.x, 480);
    expect(reloaded.yOffset, -35);
  });

  test('setEventPosition can reassign the event to a different track', () async {
    final main = await service.addTrack('Main');
    final backstory = await service.addTrack('Backstory');
    final event = await service.addEvent(trackId: main.id, label: 'Reveal');

    await service.setEventPosition(event, 200, 0, trackId: backstory.id);

    final reloaded = (await service.listEvents()).single;
    expect(reloaded.trackId, backstory.id);
  });

  test('setEventPosition without a trackId keeps the event on its own track', () async {
    final track = await service.addTrack('Main');
    final event = await service.addEvent(trackId: track.id, label: 'Reveal');

    await service.setEventPosition(event, 200, 40);

    final reloaded = (await service.listEvents()).single;
    expect(reloaded.trackId, track.id);
  });

  test('saveEvent round-trips linked ids and time label', () async {
    final track = await service.addTrack('Main');
    final event = await service.addEvent(trackId: track.id, label: 'Reveal');
    await service.saveEvent(event.copyWith(
      timeLabel: 'Day 3',
      linkedSceneIds: ['scene-1'],
      linkedCharacterIds: ['char-1'],
      linkedWorldIds: ['entry-1'],
    ));

    final reloaded = (await service.listEvents()).single;
    expect(reloaded.timeLabel, 'Day 3');
    expect(reloaded.linkedSceneIds, ['scene-1']);
    expect(reloaded.linkedCharacterIds, ['char-1']);
    expect(reloaded.linkedWorldIds, ['entry-1']);
  });

  test('listTracks returns tracks in row order', () async {
    await service.addTrack('Main');
    await service.addTrack('Backstory');
    await service.addTrack('Subplot');

    final names = (await service.listTracks()).map((t) => t.name).toList();
    expect(names, ['Main', 'Backstory', 'Subplot']);
  });

  test('moveTrack swaps row order with the neighbour', () async {
    final main = await service.addTrack('Main');
    await service.addTrack('Backstory');
    await service.addTrack('Subplot');

    await service.moveTrack(main.id, 1);

    final names = (await service.listTracks()).map((t) => t.name).toList();
    expect(names, ['Backstory', 'Main', 'Subplot']);
  });

  test('moveTrack past the end of the list is a no-op', () async {
    final main = await service.addTrack('Main');
    final backstory = await service.addTrack('Backstory');

    await service.moveTrack(backstory.id, 1);

    final names = (await service.listTracks()).map((t) => t.name).toList();
    expect(names, ['Main', 'Backstory']);
    expect((await service.listTracks()).map((t) => t.id), [main.id, backstory.id]);
  });

  test('moveTrack still reorders tracks that share the same order value', () async {
    // Real bug: tracks written before track ordering existed (or otherwise
    // sharing an order, e.g. every track defaulting to 0) made a same-value
    // swap a no-op — the up/down buttons visibly did nothing.
    await service.saveTrack(TimelineTrack(id: 'timeline-a', name: 'Main'));
    await service.saveTrack(TimelineTrack(id: 'timeline-b', name: 'Backstory'));
    // Sanity check the degenerate starting state this test is guarding against.
    expect((await service.listTracks()).map((t) => t.order).toSet(), {0});

    await service.moveTrack('timeline-a', 1);

    final names = (await service.listTracks()).map((t) => t.name).toList();
    expect(names, ['Backstory', 'Main']);
  });

  test('deleteTrack cascades to drop every event on it, leaves other tracks alone', () async {
    final main = await service.addTrack('Main');
    final backstory = await service.addTrack('Backstory');
    await service.addEvent(trackId: main.id, label: 'Main event');
    await service.addEvent(trackId: backstory.id, label: 'Backstory event');

    await service.deleteTrack(main.id);

    final tracks = await service.listTracks();
    expect(tracks.single.id, backstory.id);
    final events = await service.listEvents();
    expect(events.single.trackId, backstory.id);
  });

  test('deleteEvent removes only the targeted event', () async {
    final track = await service.addTrack('Main');
    final keep = await service.addEvent(trackId: track.id, label: 'Keep');
    final drop = await service.addEvent(trackId: track.id, label: 'Drop');

    await service.deleteEvent(drop.id);

    final remaining = await service.listEvents();
    expect(remaining.single.id, keep.id);
  });
}
