import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

  test('addEvent assigns ascending order per track', () async {
    final track = await service.addTrack('Main');
    await service.addEvent(trackId: track.id, label: 'Inciting incident');
    await service.addEvent(trackId: track.id, label: 'Midpoint');

    final events = await service.listEvents();
    expect(events.map((e) => e.label), ['Inciting incident', 'Midpoint']);
    expect(events.map((e) => e.order), [0, 1]);
  });

  test('addEvent order is independent per track', () async {
    final trackA = await service.addTrack('Main');
    final trackB = await service.addTrack('Backstory');
    await service.addEvent(trackId: trackA.id, label: 'A1');
    final b1 = await service.addEvent(trackId: trackB.id, label: 'B1');

    expect(b1.order, 0);
  });

  test('moveEvent swaps order with the neighbour', () async {
    final track = await service.addTrack('Main');
    final first = await service.addEvent(trackId: track.id, label: 'First');
    await service.addEvent(trackId: track.id, label: 'Second');

    await service.moveEvent(first.id, 1);

    final events = await service.listEvents();
    expect(events.map((e) => e.label), ['Second', 'First']);
  });

  test('moveEvent past the end of the track is a no-op', () async {
    final track = await service.addTrack('Main');
    final only = await service.addEvent(trackId: track.id, label: 'Only');

    await service.moveEvent(only.id, 1);

    final events = await service.listEvents();
    expect(events.single.order, 0);
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
