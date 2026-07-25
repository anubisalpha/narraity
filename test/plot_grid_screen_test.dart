import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/screens/plot_grid_screen.dart';
import 'package:narraity/state/library_provider.dart';
import 'package:narraity/state/manuscript_provider.dart';
import 'package:narraity/state/plot_grid_provider.dart';
import 'package:narraity/services/library_service.dart';

// Regression coverage for a real layout bug found by clicking through the
// built app: the grid rendered with every row collapsed to zero height and
// no visible text. Root cause was `Table(defaultVerticalAlignment:
// TableCellVerticalAlignment.fill)`: "fill" tells Table "don't ask me for a
// height, just stretch me to whatever the row ends up being" — with every
// cell set to fill, none of them ever assert a height, so the row-height
// computation has nothing to measure and collapses to zero (confirmed via
// `RenderTable.toStringDeep()`: "row offsets: 0.0, 0.0, 0.0"). A second,
// separate issue in the same build (nested horizontal-in-vertical
// SingleChildScrollViews with no bounded size handed between them) was fixed
// alongside it. Neither is caught by `find.text(...)` alone — the widget is
// present in the tree even when collapsed to zero size — so this test
// asserts actual pixel size, not just tree presence.
void main() {
  testWidgets('Plot Grid renders plotline names, scene headers, and non-collapsed rows',
      (tester) async {
    final projectRoot = Directory.systemTemp.createTempSync('narraity_plotgrid_screen_test_');
    addTearDown(() => projectRoot.deleteSync(recursive: true));
    final library = LibraryService(rootOverride: projectRoot);

    final container = ProviderContainer(
      overrides: [libraryServiceProvider.overrideWithValue(library)],
    );
    addTearDown(container.dispose);

    final project = (await tester.runAsync(() => library.createProject(title: 'Test Novel')))!;
    await tester.runAsync(() async {
      final structure = await container.read(manuscriptStructureProvider(project).future);
      expect(structure.allContentIds, isNotEmpty,
          reason: 'a fresh project seeds at least one scene');

      final plotGrid = await container.read(plotGridServiceProvider(project).future);
      await plotGrid.addPlotline('Main Plot', 0xFF5B8DEF);

      // Warm every provider the screen reads: an unresolved future leaves a
      // CircularProgressIndicator on screen and the text finders below empty.
      await container.read(plotlineListProvider(project).future);
      await container.read(plotPointListProvider(project).future);
      await container.read(sceneColumnsProvider(project).future);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: PlotGridScreen(project: project)),
      ),
    );
    // Not pumpAndSettle: the Scrollbar fade animation never settles on its
    // own (same reason other screen tests in this app avoid it too).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Main Plot'), findsOneWidget);

    // The row actually has visible height, not the near-zero collapse the
    // unbounded nested-scroll-view conflict produced.
    final rowHeight = tester.getSize(find.text('Main Plot')).height;
    expect(rowHeight, greaterThan(8));

    // Scene column header text is present and laid out (non-zero width).
    final headers = tester.widgetList<Text>(find.byType(Text));
    final sceneHeaderTexts = headers
        .map((t) => t.data)
        .whereType<String>()
        .where((text) => text.isNotEmpty && text != 'Main Plot');
    expect(sceneHeaderTexts, isNotEmpty, reason: 'scene column headers should render');
  });
}
