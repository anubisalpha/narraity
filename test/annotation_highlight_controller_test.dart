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
}
