import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/project.dart';
import 'package:narraity/screens/export_screen.dart';

void main() {
  final project = Project(
    id: 'p1',
    folderName: 'Test Novel',
    title: 'Test Novel',
    created: DateTime.utc(2026),
    modified: DateTime.utc(2026),
  );

  Future<void> pumpExportScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: ExportScreen(project: project)),
      ),
    );
    await tester.pump();
  }

  testWidgets('lists PDF, DOCX, EPUB, plain text, and both KDP print options',
      (tester) async {
    await pumpExportScreen(tester);

    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('Word document (.docx)'), findsOneWidget);
    expect(find.text('EPUB (e-reader/Kindle)'), findsOneWidget);
    expect(find.text('Plain text (.txt)'), findsOneWidget);
    expect(find.text('KDP Paperback (print-ready PDF)'), findsOneWidget);
    expect(find.text('KDP Hardcover (print-ready PDF)'), findsOneWidget);
  });

  testWidgets('the trim size/bleed picker is hidden until a KDP print format is selected',
      (tester) async {
    await pumpExportScreen(tester);

    expect(find.text('Trim size'), findsNothing);
    expect(find.text('Bleed'), findsNothing);
  });

  testWidgets('selecting KDP Paperback reveals the paperback trim size list and bleed toggle',
      (tester) async {
    await pumpExportScreen(tester);

    await tester.ensureVisible(find.text('KDP Paperback (print-ready PDF)'));
    await tester.pump();
    await tester.tap(find.text('KDP Paperback (print-ready PDF)'));
    await tester.pump();

    expect(find.text('Trim size'), findsOneWidget);
    expect(find.text('Bleed'), findsOneWidget);
    // The default paperback trim (6x9) shown with its "most common" note.
    expect(find.textContaining('most common for novels'), findsOneWidget);
    expect(
      find.text('Interior file only — cover generation isn\'t part of this. KDP\'s '
          'own Cover Creator handles that separately.'),
      findsOneWidget,
    );
  });

  testWidgets('selecting KDP Hardcover reveals its own trim size list, without the paperback '
      '"most common" note', (tester) async {
    await pumpExportScreen(tester);

    await tester.ensureVisible(find.text('KDP Hardcover (print-ready PDF)'));
    await tester.pump();
    await tester.tap(find.text('KDP Hardcover (print-ready PDF)'));
    await tester.pump();

    expect(find.text('Trim size'), findsOneWidget);
    expect(find.text('Bleed'), findsOneWidget);
    expect(find.textContaining('most common for novels'), findsNothing);
  });

  testWidgets('switching from KDP Paperback to a non-print format hides the picker again',
      (tester) async {
    await pumpExportScreen(tester);

    await tester.ensureVisible(find.text('KDP Paperback (print-ready PDF)'));
    await tester.pump();
    await tester.tap(find.text('KDP Paperback (print-ready PDF)'));
    await tester.pump();
    expect(find.text('Trim size'), findsOneWidget);

    await tester.ensureVisible(find.text('PDF'));
    await tester.pump();
    await tester.tap(find.text('PDF'));
    await tester.pump();
    expect(find.text('Trim size'), findsNothing);
  });
}
