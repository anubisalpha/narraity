import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:narraity/app.dart';
import 'package:narraity/services/library_service.dart';
import 'package:narraity/state/library_provider.dart';
import 'package:narraity/state/theme_provider.dart';

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
}
