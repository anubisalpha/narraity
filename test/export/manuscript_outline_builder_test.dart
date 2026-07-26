import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/export_outline.dart';
import 'package:narraity/models/manuscript.dart';
import 'package:narraity/services/export/manuscript_outline_builder.dart';

void main() {
  test('flattens front matter, nodes, and back matter in reading order', () {
    final structure = ManuscriptStructure(
      frontMatter: [SpecialSection(id: 'prologue-1', type: SpecialSectionType.prologue)],
      nodes: [
        ManuscriptNode(id: 'ch-1', title: 'Chapter 1', typeLabel: 'Chapter'),
        ManuscriptNode(id: 'ch-2', title: 'Chapter 2', typeLabel: 'Chapter'),
      ],
      backMatter: [SpecialSection(id: 'epilogue-1', type: SpecialSectionType.epilogue)],
    );

    final sections = ManuscriptOutlineBuilder.build(structure);

    expect(sections.map((s) => s.id), ['prologue-1', 'ch-1', 'ch-2', 'epilogue-1']);
    expect(sections[0].kind, ExportSectionKind.frontMatter);
    expect(sections[1].kind, ExportSectionKind.node);
    expect(sections[3].kind, ExportSectionKind.backMatter);
  });

  test('nested nodes get increasing depth, reading order is depth-first', () {
    final chapter = ManuscriptNode(
      id: 'ch-1',
      title: 'Chapter 1',
      typeLabel: 'Chapter',
      children: [
        ManuscriptNode(id: 'sc-1', title: 'Scene 1', typeLabel: 'Scene'),
        ManuscriptNode(id: 'sc-2', title: 'Scene 2', typeLabel: 'Scene'),
      ],
    );
    final structure = ManuscriptStructure(nodes: [chapter]);

    final sections = ManuscriptOutlineBuilder.build(structure);

    expect(sections.map((s) => s.id), ['ch-1', 'sc-1', 'sc-2']);
    expect(sections.map((s) => s.depth), [0, 1, 1]);
  });

  test('front and back matter are always depth 0 regardless of node nesting', () {
    final structure = ManuscriptStructure(
      frontMatter: [SpecialSection(id: 'dedication-1', type: SpecialSectionType.dedication)],
      nodes: [
        ManuscriptNode(
          id: 'ch-1',
          title: 'Chapter 1',
          typeLabel: 'Chapter',
          children: [ManuscriptNode(id: 'sc-1', title: 'Scene 1', typeLabel: 'Scene')],
        ),
      ],
    );

    final sections = ManuscriptOutlineBuilder.build(structure);

    expect(sections.first.depth, 0);
    expect(sections.first.kind, ExportSectionKind.frontMatter);
  });

  test('an empty structure produces no sections', () {
    expect(ManuscriptOutlineBuilder.build(ManuscriptStructure()), isEmpty);
  });
}
