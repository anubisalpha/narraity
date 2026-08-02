import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/content_owner.dart';
import 'package:narraity/models/series.dart';
import 'package:narraity/screens/series_detail_screen.dart';
import 'package:narraity/services/library_service.dart';
import 'package:narraity/state/library_provider.dart';
import 'package:narraity/state/manuscript_provider.dart';
import 'package:narraity/state/reference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// This is the actual point of the ContentOwner refactor: series-level
// content (characters, worldbuilding, notes, to-dos) has to be genuinely
// separate storage from any project inside the series, not just a UI label
// on the same data. Real file I/O throughout, same reason widget_test.dart's
// other tests wrap setup in runAsync — flutter_test's fake-async zone never
// resolves real disk reads.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'a series-level character is isolated from its projects\' own characters',
    (tester) async {
      final projectRoot = Directory.systemTemp.createTempSync(
        'narraity_series_content_test_',
      );
      addTearDown(() => projectRoot.deleteSync(recursive: true));
      final library = LibraryService(rootOverride: projectRoot);

      final container = ProviderContainer(
        overrides: [libraryServiceProvider.overrideWithValue(library)],
      );
      addTearDown(container.dispose);

      late Series series;
      ContentOwner seriesOwner() => ContentOwner.series(series);

      await tester.runAsync(() async {
        series = await container
            .read(seriesServiceProvider)
            .createSeries(title: 'My Saga');
        final project = await library.createProject(title: 'Book One');
        await library.saveProject(project.copyWith(seriesId: series.id));

        final seriesCharacters = await container.read(
          characterServiceProvider(seriesOwner()).future,
        );
        await seriesCharacters.create(name: 'The Chronicler');

        // Warm what the screen's sidebar reads on first build.
        await container.read(seriesListProvider.future);
        await container.read(projectListProvider.future);
        await container.read(characterListProvider(seriesOwner()).future);
        await container.read(worldListProvider(seriesOwner()).future);
        await container.read(storyNoteListProvider(seriesOwner()).future);
        await container.read(noteFoldersProvider(seriesOwner()).future);
        await container.read(todoListProvider(seriesOwner()).future);
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: SeriesDetailScreen(series: series)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Characters is the sidebar's default-selected tab — the series-level
      // character should already be visible without switching tabs.
      expect(find.text('The Chronicler'), findsOneWidget);

      // And it must actually live under the series' own folder, not the
      // project's — a project inside the series reading its own character
      // list should never see it.
      final projectOwner = ContentOwner.project(
        (await tester.runAsync(() => library.listProjects()))!.single,
      );
      final projectCharacters = await tester.runAsync(
        () => container.read(characterListProvider(projectOwner).future),
      );
      expect(projectCharacters, isEmpty);
    },
  );
}
