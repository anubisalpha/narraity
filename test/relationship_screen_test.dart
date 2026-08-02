import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/content_owner.dart';
import 'package:narraity/screens/relationship_screen.dart';
import 'package:narraity/services/library_service.dart';
import 'package:narraity/state/library_provider.dart';
import 'package:narraity/state/reference_provider.dart';
import 'package:narraity/state/relationship_provider.dart';

// Persisting the resulting relationship (real file I/O, triggered from a
// button tap) is covered by relationship_service_test.dart's addRelationship
// coverage instead of here — see widget_test.dart's own "New Project dialog"
// test for why: this codebase deliberately never taps a Save-style button
// through to a real write in a widget test, since real I/O started from a
// simulated tap runs inside flutter_test's fake-async zone and never
// resolves. What's worth testing here is the UI wiring runAsync can't touch:
// that the drag gesture actually reaches the node (it previously didn't —
// see relationship_screen.dart's _ImmediateDragRecognizer doc comment) and
// opens the dialog, and that the dragged node snaps back rather than staying
// wherever it was dropped.
void main() {
  testWidgets('dragging one character node onto another opens the relationship dialog '
      'and snaps the dragged node back', (tester) async {
    final projectRoot = Directory.systemTemp.createTempSync('narraity_relationship_screen_test_');
    addTearDown(() => projectRoot.deleteSync(recursive: true));
    final library = LibraryService(rootOverride: projectRoot);

    final container = ProviderContainer(
      overrides: [libraryServiceProvider.overrideWithValue(library)],
    );
    addTearDown(container.dispose);

    final project = (await tester.runAsync(() => library.createProject(title: 'Test Novel')))!;
    await tester.runAsync(() async {
      final characters =
          await container.read(characterServiceProvider(ContentOwner.project(project)).future);
      await characters.create(name: 'Elena');
      await characters.create(name: 'Marcus');

      await container.read(characterListProvider(ContentOwner.project(project)).future);
      await container.read(relationshipListProvider(project).future);
      await container.read(relationshipLayoutProvider(project).future);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: RelationshipScreen(project: project)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Elena'), findsOneWidget);
    expect(find.text('Marcus'), findsOneWidget);

    // .first: once the dialog opens later, its own "Character A" dropdown
    // also renders the text "Elena", making the plain finder ambiguous.
    final elenaStart = tester.getTopLeft(find.text('Elena').first);
    final elenaCenter = tester.getCenter(find.text('Elena').first);
    final marcusCenter = tester.getCenter(find.text('Marcus').first);

    final gesture = await tester.startGesture(elenaCenter);
    await tester.pump();
    await gesture.moveTo(marcusCenter);
    await tester.pump();

    // While hovering over Marcus (before release), the node shows which
    // character it would link to.
    expect(find.textContaining('→ Marcus'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('New Relationship'), findsOneWidget);

    // Elena's node snapped back to where it started rather than staying at
    // the drop point — this gesture links, it doesn't move.
    final elenaAfter = tester.getTopLeft(find.text('Elena').first);
    expect(elenaAfter, elenaStart);

    // Close without saving — persistence itself is covered at the service
    // layer (see relationship_service_test.dart).
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pump();
  });

  testWidgets('New Character button opens a name prompt', (tester) async {
    final projectRoot = Directory.systemTemp.createTempSync('narraity_relationship_newchar_test_');
    addTearDown(() => projectRoot.deleteSync(recursive: true));
    final library = LibraryService(rootOverride: projectRoot);

    final container = ProviderContainer(
      overrides: [libraryServiceProvider.overrideWithValue(library)],
    );
    addTearDown(container.dispose);

    final project = (await tester.runAsync(() => library.createProject(title: 'Test Novel')))!;
    await tester.runAsync(() async {
      await container.read(characterListProvider(ContentOwner.project(project)).future);
      await container.read(relationshipListProvider(project).future);
      await container.read(relationshipLayoutProvider(project).future);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: RelationshipScreen(project: project)),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.person_add_alt_1));
    await tester.pump();

    expect(find.text('New Character'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);

    // Not tapping Save: real character creation is real file I/O, which
    // never resolves inside flutter_test's fake-async zone when triggered
    // from a simulated tap (see the comment atop this file).
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pump();
    expect(find.text('New Character'), findsNothing);
  });
}
