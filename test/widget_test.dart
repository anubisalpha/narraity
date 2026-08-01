import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:narraity/app.dart';
import 'package:narraity/models/project.dart';
import 'package:narraity/services/library_service.dart';
import 'package:narraity/state/library_provider.dart';
import 'package:narraity/state/manuscript_provider.dart';
import 'package:narraity/state/reference_panel_provider.dart';
import 'package:narraity/state/reference_provider.dart';
import 'package:narraity/state/theme_provider.dart';
import 'package:narraity/state/vault_provider.dart';
import 'package:narraity/widgets/profile_editor.dart';
import 'package:narraity/widgets/reference_panel.dart';

// Project creation itself (real file I/O) is covered by the pure-Dart
// library_service_test.dart, which doesn't fight flutter_test's fake-time
// zone. This file sticks to widget-tree behaviour.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tempDir = Directory.systemTemp.createTempSync('narraity_widget_test_');
  tearDownAll(() => tempDir.deleteSync(recursive: true));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App boots to an empty library with a New Project action', (tester) async {
    final container = ProviderContainer(
      overrides: [
        libraryServiceProvider.overrideWithValue(LibraryService(rootOverride: tempDir)),
      ],
    );
    addTearDown(container.dispose);

    // Await the real future outside pumpWidget: testWidgets' whole callback
    // runs inside a FakeAsync zone, and real filesystem I/O never resolves
    // under fake time — runAsync steps outside it for this one await.
    await tester.runAsync(() => container.read(projectListProvider.future));
    await tester.runAsync(() => container.read(seriesListProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const NarraityApp()),
    );
    await tester.pump();

    expect(find.text('Narraity'), findsOneWidget);
    expect(find.text('No projects yet'), findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'New Project'), findsOneWidget);
  });

  testWidgets('New Project dialog validates title and can be cancelled', (tester) async {
    final container = ProviderContainer(
      overrides: [
        libraryServiceProvider.overrideWithValue(LibraryService(rootOverride: tempDir)),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(projectListProvider.future));
    await tester.runAsync(() => container.read(seriesListProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const NarraityApp()),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FloatingActionButton, 'New Project'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Title'), findsOneWidget);

    // Empty title is rejected.
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    expect(find.text('Title is required'), findsOneWidget);

    // Cancel closes the dialog without creating anything.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('No projects yet'), findsOneWidget);
  });

  testWidgets('Settings > Appearance switches theme mode', (tester) async {
    final container = ProviderContainer(
      overrides: [
        libraryServiceProvider.overrideWithValue(LibraryService(rootOverride: tempDir)),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(projectListProvider.future));
    await tester.runAsync(() => container.read(seriesListProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const NarraityApp()),
    );
    await tester.pump();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsWidgets);
    expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  testWidgets('Settings > Backup & Vault offers first-time setup', (tester) async {
    final container = ProviderContainer(
      overrides: [
        libraryServiceProvider.overrideWithValue(LibraryService(rootOverride: tempDir)),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(projectListProvider.future));
    await tester.runAsync(() => container.read(seriesListProvider.future));
    await tester.runAsync(() => container.read(vaultStatusProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const NarraityApp()),
    );
    await tester.pump();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backup & Vault'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Set up vault password'), findsOneWidget);
    expect(find.textContaining('no way to recover this password'), findsOneWidget);
  });

  // Creating and editing reference entries goes through real file I/O, which
  // never resolves inside flutter_test's fake-time zone — that behaviour is
  // covered by profile_service_test.dart and story_notes_service_test.dart.
  // What's worth testing here is the wiring those tests can't see: that the
  // shell exposes the new panels and that selecting an entry routes the main
  // pane to it.
  testWidgets('Project shell exposes reference panels and opens a character',
      (tester) async {
    // A separate root: this test needs a real project, while the tests above
    // assert the shared library is empty.
    final projectRoot = Directory.systemTemp.createTempSync('narraity_shell_test_');
    addTearDown(() => projectRoot.deleteSync(recursive: true));
    final library = LibraryService(rootOverride: projectRoot);

    final container = ProviderContainer(
      overrides: [libraryServiceProvider.overrideWithValue(library)],
    );
    addTearDown(container.dispose);

    final project =
        (await tester.runAsync(() => library.createProject(title: 'Test Novel')))!;
    await tester.runAsync(() async {
      final characters = await container.read(characterServiceProvider(project).future);
      await characters.create(name: 'Elena Vance');

      // Warm every provider the shell's tabs read: an unresolved future leaves
      // a CircularProgressIndicator spinning, which pumpAndSettle waits on
      // forever.
      await container.read(manuscriptStructureProvider(project).future);
      await container.read(characterListProvider(project).future);
      await container.read(worldListProvider(project).future);
      await container.read(storyNoteListProvider(project).future);
      await container.read(noteFoldersProvider(project).future);
      await container.read(todoListProvider(project).future);
    });
    container.read(currentProjectProvider.notifier).state = project;

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const NarraityApp()),
    );
    await tester.pump();

    // Manuscript, Characters, World, Notes, To-dos.
    expect(find.byType(Tab), findsNWidgets(5));

    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // tab transition

    expect(find.text('Elena Vance'), findsOneWidget);

    await tester.tap(find.text('Elena Vance'));
    await tester.pump();

    expect(container.read(openReferenceProvider)?.kind, ReferenceKind.character);
    expect(find.byType(ProfileEditor), findsOneWidget,
        reason: 'selecting a character must route the main pane to its profile');
  });

  testWidgets('Reference Panel shows quick-reference fields for a mentioned character',
      (tester) async {
    final projectRoot = Directory.systemTemp.createTempSync('narraity_refpanel_test_');
    addTearDown(() => projectRoot.deleteSync(recursive: true));
    final library = LibraryService(rootOverride: projectRoot);

    final container = ProviderContainer(
      overrides: [libraryServiceProvider.overrideWithValue(library)],
    );
    addTearDown(container.dispose);

    final project =
        (await tester.runAsync(() => library.createProject(title: 'Test Novel')))!;
    await tester.runAsync(() async {
      final characters = await container.read(characterServiceProvider(project).future);
      final elena = await characters.create(name: 'Elena Vance');
      await characters.save(elena.copyWith(
        fields: {...elena.fields, 'Role': 'Captain of the guard'},
        quickRef: ['Role'],
      ));

      await container.read(manuscriptStructureProvider(project).future);
      await container.read(characterListProvider(project).future);
      await container.read(worldListProvider(project).future);
      await container.read(storyNoteListProvider(project).future);
      await container.read(noteFoldersProvider(project).future);
      await container.read(todoListProvider(project).future);
    });
    container.read(currentProjectProvider.notifier).state = project;

    // What SceneEditor publishes after scanning `[[Elena Vance]]` in the prose.
    container.read(sceneMentionedNamesProvider.notifier).state = ['Elena Vance'];
    await tester.runAsync(
        () => container.read(referencePanelContentProvider(project).future));

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const NarraityApp()),
    );
    await tester.pump();

    expect(find.byType(ReferencePanel), findsOneWidget);
    // The starred field shows with its value; unstarred fields stay hidden.
    expect(find.text('Role'), findsOneWidget);
    expect(find.text('Captain of the guard'), findsOneWidget);
    expect(find.text('Backstory'), findsNothing,
        reason: 'only starred fields belong on a card');

    // A mention with no matching profile offers to create one.
    container.read(sceneMentionedNamesProvider.notifier).state = ['Nobody At All'];
    await tester.runAsync(
        () => container.read(referencePanelContentProvider(project).future));
    await tester.pump();

    expect(find.textContaining('No profile named "Nobody At All"'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Create'), findsOneWidget);
  });

  testWidgets(
      'tapping a project inside a series list actually opens it (regression: SeriesDetailScreen '
      'is a pushed route on top of NarraityApp\'s home; setting currentProjectProvider swaps '
      '`home` from LibraryScreen to ProjectShellScreen underneath, invisibly, unless the pushed '
      'route is popped back to the root first)', (tester) async {
    final projectRoot = Directory.systemTemp.createTempSync('narraity_series_open_test_');
    addTearDown(() => projectRoot.deleteSync(recursive: true));
    final library = LibraryService(rootOverride: projectRoot);

    final container = ProviderContainer(
      overrides: [libraryServiceProvider.overrideWithValue(library)],
    );
    addTearDown(container.dispose);

    late Project project;
    await tester.runAsync(() async {
      final series = await container.read(seriesServiceProvider).createSeries(title: 'My Series');
      project = await library.createProject(title: 'Book One');
      await library.saveProject(project.copyWith(seriesId: series.id));

      // Warm the library screen's own lists too — otherwise a single pump()
      // catches them mid-load and neither the series card nor the project
      // card exists yet to tap.
      await container.read(seriesListProvider.future);
      final loadedProjects = await container.read(projectListProvider.future);

      // `Project` has no `==`/`hashCode` override, so warming providers
      // keyed by `project` (the instance this test created directly) would
      // do nothing for `SeriesDetailScreen`, which gets its own, separately
      // *deserialized* `Project` instance from `projectListProvider` —  a
      // different object identity for the same on-disk project, and
      // therefore a different family-provider cache key. Warm using the
      // exact instance the screen will actually see instead.
      final loadedProject = loadedProjects.single;
      await container.read(manuscriptStructureProvider(loadedProject).future);
      await container.read(characterListProvider(loadedProject).future);
      await container.read(worldListProvider(loadedProject).future);
      await container.read(storyNoteListProvider(loadedProject).future);
      await container.read(noteFoldersProvider(loadedProject).future);
      await container.read(todoListProvider(loadedProject).future);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const NarraityApp()),
    );
    await tester.pump();

    // Open the series from the library grid (MaterialPageRoute's push
    // transition needs an explicit duration to complete, same pattern as
    // the tab-transition wait above).
    await tester.tap(find.text('My Series'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Book One'), findsOneWidget,
        reason: 'should now be looking at the series detail screen, showing its one project');

    // Tap the project card inside the series.
    await tester.tap(find.text('Book One'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // The project shell (its tab bar) should now be visible — not the
    // series detail screen still sitting on top, unopened.
    expect(find.byType(Tab), findsNWidgets(5),
        reason: 'tapping a project inside a series list should open its project shell');
  });
}
