import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/screens/review_export_screen.dart';
import 'package:narraity/services/library_service.dart';
import 'package:narraity/state/library_provider.dart';
import 'package:narraity/state/manuscript_provider.dart';

void main() {
  testWidgets('lists scenes as a checklist and enables Export once one is selected',
      (tester) async {
    final projectRoot =
        Directory.systemTemp.createTempSync('narraity_review_screen_test_');
    addTearDown(() => projectRoot.deleteSync(recursive: true));
    final library = LibraryService(rootOverride: projectRoot);

    final container = ProviderContainer(
      overrides: [libraryServiceProvider.overrideWithValue(library)],
    );
    addTearDown(container.dispose);

    final project = (await tester.runAsync(() => library.createProject(title: 'Test Novel')))!;
    await tester.runAsync(() async {
      final structure = await container.read(manuscriptStructureProvider(project).future);
      expect(structure.allContentIds, isNotEmpty);
      await container.read(sceneColumnsProvider(project).future);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ReviewExportScreen(project: project)),
      ),
    );
    await tester.pump();

    // The default seed is Act > Chapter > Scene, and sceneColumnsProvider
    // lists every content id (not just leaf scenes) — so a fresh project
    // has three rows: the act, the chapter, and the scene.
    expect(find.text('Scene 1'), findsOneWidget);
    expect(find.text('0 of 3 selected'), findsOneWidget);

    // FilledButton.icon returns a private FilledButton subclass, so
    // find.widgetWithText<FilledButton> (exact-type match) finds nothing —
    // byWidgetPredicate's `is FilledButton` check does match subtypes.
    final exportButtonFinder = find.byWidgetPredicate((w) => w is FilledButton);
    expect(find.text('Select scenes to export'), findsOneWidget);
    expect(tester.widget<FilledButton>(exportButtonFinder).onPressed, isNull);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Scene 1'));
    await tester.pump();

    expect(find.text('1 of 3 selected'), findsOneWidget);
    expect(find.text('Export 1 scene(s) for review'), findsOneWidget);
    expect(tester.widget<FilledButton>(exportButtonFinder).onPressed, isNotNull);
  });

  testWidgets('Select All / Clear toggle every checkbox at once', (tester) async {
    final projectRoot =
        Directory.systemTemp.createTempSync('narraity_review_screen_test2_');
    addTearDown(() => projectRoot.deleteSync(recursive: true));
    final library = LibraryService(rootOverride: projectRoot);

    final container = ProviderContainer(
      overrides: [libraryServiceProvider.overrideWithValue(library)],
    );
    addTearDown(container.dispose);

    final project = (await tester.runAsync(() => library.createProject(title: 'Test Novel')))!;
    await tester.runAsync(() async {
      await container.read(manuscriptStructureProvider(project).future);
      await container.read(sceneColumnsProvider(project).future);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ReviewExportScreen(project: project)),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Select All'));
    await tester.pump();
    expect(find.text('3 of 3 selected'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(find.text('0 of 3 selected'), findsOneWidget);
  });
}
