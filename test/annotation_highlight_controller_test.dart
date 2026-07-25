import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/annotation.dart';
import 'package:narraity/widgets/annotation_highlight_controller.dart';

Annotation _annotation({
  required AnnotationKind kind,
  int? color,
}) =>
    Annotation(
      id: 'a1',
      sceneId: 'scene-1',
      kind: kind,
      anchor: const TextAnchor(start: 0, end: 5, quotedText: 'Elena'),
      color: color,
      created: DateTime(2026, 1, 1),
      modified: DateTime(2026, 1, 1),
    );

void main() {
  testWidgets('with no annotations, falls back to plain text rendering', (tester) async {
    final controller = AnnotationHighlightController(text: 'Elena stepped inside.');
    late BuildContext capturedContext;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          capturedContext = context;
          return TextField(controller: controller);
        }),
      ),
    ));

    final span =
        controller.buildTextSpan(context: capturedContext, withComposing: false);
    expect(span.toPlainText(), 'Elena stepped inside.');
    expect(span.children, isNull);
  });

  testWidgets('paints a highlight span with its stored color', (tester) async {
    final controller = AnnotationHighlightController(text: 'Elena stepped inside.');
    late BuildContext capturedContext;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          capturedContext = context;
          return TextField(controller: controller);
        }),
      ),
    ));

    controller.annotations = [
      (
        _annotation(kind: AnnotationKind.highlight, color: 0xFFFFF59D),
        const AnchorResolution(status: AnchorStatus.exact, start: 0, end: 5),
      ),
    ];

    final span =
        controller.buildTextSpan(context: capturedContext, withComposing: false);
    expect(span.toPlainText(), 'Elena stepped inside.');

    final children = span.children!;
    expect(children, isNotEmpty);
    final highlighted = children.first as TextSpan;
    expect(highlighted.text, 'Elena');
    expect(highlighted.style!.backgroundColor, const Color(0xFFFFF59D));
  });

  testWidgets('an orphaned annotation gets the wavy red flag decoration', (tester) async {
    final controller = AnnotationHighlightController(text: 'Marcus stepped inside.');
    late BuildContext capturedContext;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          capturedContext = context;
          return TextField(controller: controller);
        }),
      ),
    ));

    controller.annotations = [
      (
        _annotation(kind: AnnotationKind.comment),
        const AnchorResolution(status: AnchorStatus.orphaned, start: 0, end: 6),
      ),
    ];

    final span =
        controller.buildTextSpan(context: capturedContext, withComposing: false);
    final flagged = span.children!.first as TextSpan;
    expect(flagged.style!.decorationStyle, TextDecorationStyle.wavy);
    expect(flagged.style!.decorationColor, Colors.red);
  });

  testWidgets('overlapping ranges: the earlier-starting one wins', (tester) async {
    final controller = AnnotationHighlightController(text: 'Elena stepped inside.');
    late BuildContext capturedContext;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          capturedContext = context;
          return TextField(controller: controller);
        }),
      ),
    ));

    controller.annotations = [
      (
        _annotation(kind: AnnotationKind.highlight, color: 0xFFFFF59D),
        const AnchorResolution(status: AnchorStatus.exact, start: 0, end: 5),
      ),
      (
        _annotation(kind: AnnotationKind.stickyNote),
        const AnchorResolution(status: AnchorStatus.exact, start: 2, end: 8),
      ),
    ];

    final span =
        controller.buildTextSpan(context: capturedContext, withComposing: false);
    // Total plain text is preserved even though the second range is clipped.
    expect(span.toPlainText(), 'Elena stepped inside.');
  });

  group('speakingRange (Read Aloud)', () {
    testWidgets('paints a speaking range with no annotations present', (tester) async {
      final controller = AnnotationHighlightController(text: 'Elena stepped inside.');
      late BuildContext capturedContext;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            capturedContext = context;
            return TextField(controller: controller);
          }),
        ),
      ));

      controller.speakingRange = (0, 5);

      final span =
          controller.buildTextSpan(context: capturedContext, withComposing: false);
      expect(span.toPlainText(), 'Elena stepped inside.');
      final spoken = span.children!.first as TextSpan;
      expect(spoken.text, 'Elena');
      expect(spoken.style!.backgroundColor, const Color(0xFFFFB74D));
    });

    testWidgets('overlays on top of an existing highlight rather than replacing it',
        (tester) async {
      final controller = AnnotationHighlightController(text: 'Elena stepped inside.');
      late BuildContext capturedContext;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            capturedContext = context;
            return TextField(controller: controller);
          }),
        ),
      ));

      controller.annotations = [
        (
          _annotation(kind: AnnotationKind.highlight, color: 0xFFFFF59D),
          const AnchorResolution(status: AnchorStatus.exact, start: 0, end: 21),
        ),
      ];
      controller.speakingRange = (6, 13); // "stepped"

      final span =
          controller.buildTextSpan(context: capturedContext, withComposing: false);
      expect(span.toPlainText(), 'Elena stepped inside.');

      // Three pieces: highlighted-only, highlighted+speaking, highlighted-only.
      final children = span.children!;
      expect(children.map((c) => c.toPlainText()), ['Elena ', 'stepped', ' inside.']);
      final spokenPiece = children[1] as TextSpan;
      expect(spokenPiece.style!.backgroundColor, const Color(0xFFFFB74D));
    });

    testWidgets('clearing speakingRange stops painting it', (tester) async {
      final controller = AnnotationHighlightController(text: 'Elena stepped inside.');
      late BuildContext capturedContext;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            capturedContext = context;
            return TextField(controller: controller);
          }),
        ),
      ));

      controller.speakingRange = (0, 5);
      controller.speakingRange = null;

      final span =
          controller.buildTextSpan(context: capturedContext, withComposing: false);
      expect(span.children, isNull);
      expect(span.toPlainText(), 'Elena stepped inside.');
    });
  });

  group('misspelledRanges (spell check)', () {
    testWidgets('paints a wavy red underline under each misspelled range',
        (tester) async {
      final controller =
          AnnotationHighlightController(text: 'Elena stpped inside.');
      late BuildContext capturedContext;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            capturedContext = context;
            return TextField(controller: controller);
          }),
        ),
      ));

      controller.misspelledRanges = [(6, 12)]; // "stpped"

      final span =
          controller.buildTextSpan(context: capturedContext, withComposing: false);
      expect(span.toPlainText(), 'Elena stpped inside.');
      final children = span.children!;
      expect(children.map((c) => c.toPlainText()), ['Elena ', 'stpped', ' inside.']);
      final flagged = children[1] as TextSpan;
      expect(flagged.style!.decorationStyle, TextDecorationStyle.wavy);
      expect(flagged.style!.decorationColor, Colors.red);
    });

    testWidgets('paints multiple misspelled ranges independently', (tester) async {
      final controller =
          AnnotationHighlightController(text: 'Elena stpped insid the doorway.');
      late BuildContext capturedContext;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            capturedContext = context;
            return TextField(controller: controller);
          }),
        ),
      ));

      controller.misspelledRanges = [(6, 12), (13, 18)]; // "stpped", "insid"

      final span =
          controller.buildTextSpan(context: capturedContext, withComposing: false);
      final children = span.children!;
      expect(
        children.map((c) => c.toPlainText()),
        ['Elena ', 'stpped', ' ', 'insid', ' the doorway.'],
      );
      expect(
        (children[1] as TextSpan).style!.decorationStyle,
        TextDecorationStyle.wavy,
      );
      expect(
        (children[3] as TextSpan).style!.decorationStyle,
        TextDecorationStyle.wavy,
      );
    });

    testWidgets('a misspelled range and the speaking range compose correctly',
        (tester) async {
      final controller =
          AnnotationHighlightController(text: 'Elena stpped inside.');
      late BuildContext capturedContext;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            capturedContext = context;
            return TextField(controller: controller);
          }),
        ),
      ));

      controller.misspelledRanges = [(6, 12)]; // "stpped"
      controller.speakingRange = (0, 5); // "Elena"

      final span =
          controller.buildTextSpan(context: capturedContext, withComposing: false);
      expect(span.toPlainText(), 'Elena stpped inside.');

      final children = span.children!;
      final spoken = children.first as TextSpan;
      expect(spoken.text, 'Elena');
      expect(spoken.style!.backgroundColor, const Color(0xFFFFB74D));

      final misspelled = children.firstWhere((c) => c.toPlainText() == 'stpped') as TextSpan;
      expect(misspelled.style!.decorationStyle, TextDecorationStyle.wavy);
    });

    testWidgets('clearing misspelledRanges stops painting them', (tester) async {
      final controller =
          AnnotationHighlightController(text: 'Elena stpped inside.');
      late BuildContext capturedContext;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            capturedContext = context;
            return TextField(controller: controller);
          }),
        ),
      ));

      controller.misspelledRanges = [(6, 12)];
      controller.misspelledRanges = [];

      final span =
          controller.buildTextSpan(context: capturedContext, withComposing: false);
      expect(span.children, isNull);
      expect(span.toPlainText(), 'Elena stpped inside.');
    });
  });
}
