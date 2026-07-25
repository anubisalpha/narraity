import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/screens/timeline_screen.dart';
import 'package:narraity/services/library_service.dart';
import 'package:narraity/state/library_provider.dart';
import 'package:narraity/state/timeline_provider.dart';

// Persisting the drag (real file I/O via TimelineService.setEventPosition,
// triggered from the drag's onEnd) is covered by timeline_service_test.dart
// instead of here — same reasoning as relationship_screen_test.dart: real
// I/O started from a simulated gesture runs inside flutter_test's fake-async
// zone and never resolves. What's worth testing here is the thing runAsync
// can't touch: that the drag gesture actually moves the card, and moves it
// in two dimensions (x and yOffset) rather than only being able to nudge a
// left-to-right order like the old model did.
void main() {
  testWidgets('dragging an event card moves it freely in both axes', (tester) async {
    final projectRoot = Directory.systemTemp.createTempSync('narraity_timeline_screen_test_');
    addTearDown(() => projectRoot.deleteSync(recursive: true));
    final library = LibraryService(rootOverride: projectRoot);

    final container = ProviderContainer(
      overrides: [libraryServiceProvider.overrideWithValue(library)],
    );
    addTearDown(container.dispose);

    final project = (await tester.runAsync(() => library.createProject(title: 'Test Novel')))!;
    await tester.runAsync(() async {
      final timeline = await container.read(timelineServiceProvider(project).future);
      final track = await timeline.addTrack('Main');
      await timeline.addEvent(trackId: track.id, label: 'Reveal');

      await container.read(timelineTrackListProvider(project).future);
      await container.read(timelineEventListProvider(project).future);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: TimelineScreen(project: project)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Reveal'), findsOneWidget);

    final start = tester.getTopLeft(find.text('Reveal'));

    final gesture = await tester.startGesture(tester.getCenter(find.text('Reveal')));
    await tester.pump();
    // A diagonal drag: proves both x (time) and y (stagger) move freely,
    // not just a left-to-right nudge.
    await gesture.moveBy(const Offset(120, -50));
    await tester.pump();

    final midDrag = tester.getTopLeft(find.text('Reveal'));
    expect(midDrag.dx - start.dx, closeTo(120, 0.5));
    expect(midDrag.dy - start.dy, closeTo(-50, 0.5));

    await gesture.up();
    await tester.pump();
  });

  testWidgets('dragging a card past the row midpoint lands it near the next track\'s baseline',
      (tester) async {
    final projectRoot = Directory.systemTemp.createTempSync('narraity_timeline_swap_test_');
    addTearDown(() => projectRoot.deleteSync(recursive: true));
    final library = LibraryService(rootOverride: projectRoot);

    final container = ProviderContainer(
      overrides: [libraryServiceProvider.overrideWithValue(library)],
    );
    addTearDown(container.dispose);

    final project = (await tester.runAsync(() => library.createProject(title: 'Test Novel')))!;
    await tester.runAsync(() async {
      final timeline = await container.read(timelineServiceProvider(project).future);
      final main = await timeline.addTrack('Main');
      await timeline.addTrack('Backstory');
      await timeline.addEvent(trackId: main.id, label: 'Reveal');

      await container.read(timelineTrackListProvider(project).future);
      await container.read(timelineEventListProvider(project).future);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: TimelineScreen(project: project)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final startY = tester.getCenter(find.text('Reveal')).dy;

    final gesture = await tester.startGesture(tester.getCenter(find.text('Reveal')));
    await tester.pump();
    // Rows are 220px apart (_rowHeight) — dragging down by that much clears
    // the midpoint into "Backstory"'s row, which is the threshold that
    // decides reassignment (persistence of that decision is covered by
    // timeline_service_test.dart's setEventPosition/trackId coverage).
    await gesture.moveBy(const Offset(0, 220));
    await tester.pump();

    final draggedY = tester.getCenter(find.text('Reveal')).dy;
    expect(draggedY - startY, closeTo(220, 0.5));

    await gesture.up();
    await tester.pump();
  });

  testWidgets('track sidebar disables move-up on the first track and move-down on the last',
      (tester) async {
    final projectRoot = Directory.systemTemp.createTempSync('narraity_timeline_sidebar_test_');
    addTearDown(() => projectRoot.deleteSync(recursive: true));
    final library = LibraryService(rootOverride: projectRoot);

    final container = ProviderContainer(
      overrides: [libraryServiceProvider.overrideWithValue(library)],
    );
    addTearDown(container.dispose);

    final project = (await tester.runAsync(() => library.createProject(title: 'Test Novel')))!;
    await tester.runAsync(() async {
      final timeline = await container.read(timelineServiceProvider(project).future);
      await timeline.addTrack('Main');
      await timeline.addTrack('Backstory');

      await container.read(timelineTrackListProvider(project).future);
      await container.read(timelineEventListProvider(project).future);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: TimelineScreen(project: project)),
      ),
    );
    await tester.pump();

    final upButtons = tester.widgetList<IconButton>(find.widgetWithIcon(IconButton, Icons.arrow_upward));
    final downButtons =
        tester.widgetList<IconButton>(find.widgetWithIcon(IconButton, Icons.arrow_downward));

    expect(upButtons.first.onPressed, isNull, reason: 'the first track cannot move further up');
    expect(downButtons.last.onPressed, isNull, reason: 'the last track cannot move further down');
    expect(downButtons.first.onPressed, isNotNull);
    expect(upButtons.last.onPressed, isNotNull);
  });
}
