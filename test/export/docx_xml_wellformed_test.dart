import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/manuscript.dart';
import 'package:narraity/models/project.dart';
import 'package:narraity/services/export/docx_exporter.dart';
import 'package:narraity/services/manuscript_service.dart';
import 'package:xml/xml.dart';

/// Extra confidence check beyond content assertions: parses the generated
/// document.xml with a real XML parser (`XmlDocument.parse` throws on
/// malformed XML) against a realistic manuscript exercising every block
/// type at once. There's no copy of Word on this machine to open the
/// result in directly, so "a real XML parser accepts it" is the strongest
/// verification available.
void main() {
  test('generated document.xml is well-formed XML for a realistic manuscript', () async {
    final dir = Directory.systemTemp.createTempSync('narraity_docx_wellformed_test_');
    addTearDown(() => dir.deleteSync(recursive: true));

    final manuscriptService = ManuscriptService(dir);
    final exporter = DocxExporter(dir);
    final project = Project(
      id: 'p1',
      folderName: 'n',
      title: 'My Novel',
      subtitle: 'A Subtitle & Test <Case>',
      author: 'Author "Quotes"',
      created: DateTime.now(),
      modified: DateTime.now(),
    );
    final structure = ManuscriptStructure(
      frontMatter: [SpecialSection(id: 'prologue-1', type: SpecialSectionType.prologue)],
      nodes: [
        ManuscriptNode(
          id: 'ch-1',
          title: 'Chapter 1',
          typeLabel: 'Chapter',
          children: [ManuscriptNode(id: 'sc-1', title: 'Scene 1', typeLabel: 'Scene')],
        ),
      ],
      backMatter: [SpecialSection(id: 'epilogue-1', type: SpecialSectionType.epilogue)],
    );
    await manuscriptService.writeScene(SceneDoc(
      id: 'prologue-1',
      title: 'Prologue',
      content: 'A **bold** start.\n\n> A quote here.\n\n***\n\nAfter break.',
    ));
    await manuscriptService.writeScene(SceneDoc(
      id: 'ch-1',
      title: 'Chapter 1',
      content: 'Chapter prose with *italic* and ~~strike~~ and Tom & Jerry < 5 > 0.',
    ));
    await manuscriptService.writeScene(SceneDoc(
      id: 'sc-1',
      title: 'Scene 1',
      content: 'Scene prose.\nSecond line.\n\n## An inline heading\n\nMore text.',
    ));
    await manuscriptService.writeScene(
      SceneDoc(id: 'epilogue-1', title: 'Epilogue', content: 'The end.'),
    );

    final bytes = await exporter.buildBytes(project, structure);
    final archive = ZipDecoder().decodeBytes(bytes);
    final docXml =
        String.fromCharCodes(archive.findFile('word/document.xml')!.content as List<int>);

    final parsed = XmlDocument.parse(docXml); // throws XmlParserException if malformed
    expect(parsed.rootElement.name.local, 'document');

    // Spot-check the escaping actually round-trips through a real parser
    // (not just "the string contains &amp;", but that the parsed text node
    // reads back as the original unescaped character).
    final allText = parsed.rootElement.descendants.whereType<XmlText>().map((t) => t.value).join();
    expect(allText, contains('Tom & Jerry < 5 > 0'));
  });
}
