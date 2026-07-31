import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/manuscript.dart';
import 'package:narraity/models/manuscript_import.dart';
import 'package:narraity/models/project.dart';
import 'package:narraity/services/export/docx_exporter.dart';
import 'package:narraity/services/import/docx_importer.dart';
import 'package:narraity/services/manuscript_service.dart';

void main() {
  test('throws ImportParseException for something that is not a zip at all', () {
    expect(
      () => DocxImporter.parse(Uint8List.fromList('not a docx file'.codeUnits)),
      throwsA(isA<ImportParseException>()),
    );
  });

  group('round-trip against Narraity\'s own DOCX exporter', () {
    late Directory projectDir;
    late ManuscriptService manuscriptService;

    setUp(() {
      projectDir = Directory.systemTemp.createTempSync('narraity_docx_import_test_');
      manuscriptService = ManuscriptService(projectDir);
    });

    tearDown(() => projectDir.deleteSync(recursive: true));

    Future<List<ImportedNode>> exportThenImport(Project project, ManuscriptStructure structure) async {
      final bytes = await DocxExporter(projectDir).buildBytes(project, structure);
      return DocxImporter.parse(bytes);
    }

    test('nested chapter/scene structure and prose survive export then import', () async {
      // No title/author: the exporter's title page is empty when the
      // project has neither, isolating this test to the manuscript
      // structure itself -- the title-page-leak case is its own test below.
      final project = Project(
        id: 'p1',
        folderName: 'My Novel',
        title: '',
        created: DateTime.utc(2026),
        modified: DateTime.utc(2026),
      );
      final structure = ManuscriptStructure(nodes: [
        ManuscriptNode(
          id: 'ch-1',
          title: 'Chapter One',
          typeLabel: 'Chapter',
          children: [
            ManuscriptNode(id: 'sc-1', title: 'Scene A', typeLabel: 'Scene'),
            ManuscriptNode(id: 'sc-2', title: 'Scene B', typeLabel: 'Scene'),
          ],
        ),
        ManuscriptNode(id: 'ch-2', title: 'Chapter Two', typeLabel: 'Chapter'),
      ]);

      await manuscriptService.writeScene(
        SceneDoc(id: 'ch-1', title: 'Chapter One', content: 'Chapter intro text.'),
      );
      await manuscriptService.writeScene(
        SceneDoc(id: 'sc-1', title: 'Scene A', content: 'Some **bold** and *italic* text.'),
      );
      await manuscriptService.writeScene(
        SceneDoc(id: 'sc-2', title: 'Scene B', content: 'First half.\n***\nSecond half.'),
      );
      await manuscriptService.writeScene(
        SceneDoc(id: 'ch-2', title: 'Chapter Two', content: 'Second chapter text.'),
      );

      final imported = await exportThenImport(project, structure);

      expect(imported, hasLength(2));
      expect(imported[0].title, 'Chapter One');
      expect(imported[0].content, contains('Chapter intro text.'));
      expect(imported[0].children, hasLength(2));
      expect(imported[0].children[0].title, 'Scene A');
      expect(imported[0].children[0].content, contains('**bold**'));
      expect(imported[0].children[0].content, contains('*italic*'));
      expect(imported[0].children[1].title, 'Scene B');
      expect(imported[0].children[1].content, contains('First half.\n***\nSecond half.'));

      expect(imported[1].title, 'Chapter Two');
      expect(imported[1].content, contains('Second chapter text.'));
      expect(imported[1].children, isEmpty);
    });

    test('a title page ahead of the first heading is kept as a leading node, not dropped', () async {
      // Documents this deliberate trade-off: front matter before the first
      // heading has no heading of its own to attach to, so it becomes an
      // implicit leading node rather than being silently discarded. Real
      // Word/Dabble exports with their own title page will do the same --
      // expected cleanup is deleting/merging that node after import, not
      // losing the content outright.
      final project = Project(
        id: 'p1',
        folderName: 'My Novel',
        title: 'My Novel',
        author: 'Jane Author',
        created: DateTime.utc(2026),
        modified: DateTime.utc(2026),
      );
      final structure = ManuscriptStructure(
        nodes: [ManuscriptNode(id: 'ch-1', title: 'Chapter One', typeLabel: 'Chapter')],
      );
      await manuscriptService.writeScene(
        SceneDoc(id: 'ch-1', title: 'Chapter One', content: 'Real chapter text.'),
      );

      final imported = await exportThenImport(project, structure);

      expect(imported, hasLength(2));
      expect(imported[0].title, 'Chapter 1');
      expect(imported[0].content, contains('My Novel'));
      expect(imported[0].content, contains('by Jane Author'));
      expect(imported[1].title, 'Chapter One');
      expect(imported[1].content, contains('Real chapter text.'));
    });
  });

  group('named heading styles (typical of Word/Dabble exports, not Narraity\'s own)', () {
    Uint8List buildDocx(String bodyXml) {
      const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '</Types>';
      const rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
          'Target="word/document.xml"/></Relationships>';
      final documentXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
          '<w:body>$bodyXml</w:body></w:document>';

      final archive = Archive();
      void addFile(String path, String content) {
        final bytes = utf8.encode(content);
        archive.addFile(ArchiveFile(path, bytes.length, bytes));
      }

      addFile('[Content_Types].xml', contentTypes);
      addFile('_rels/.rels', rels);
      addFile('word/document.xml', documentXml);
      return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    }

    String heading(String styleId, String text) =>
        '<w:p><w:pPr><w:pStyle w:val="$styleId"/></w:pPr>'
        '<w:r><w:t>$text</w:t></w:r></w:p>';

    String paragraph(String text) => '<w:p><w:r><w:t>$text</w:t></w:r></w:p>';

    test('Heading1/Heading2 styleIds nest regardless of localized display name', () {
      final bytes = buildDocx(
        heading('Heading1', 'Chapter One') +
            paragraph('Opening line.') +
            heading('Heading2', 'Scene A') +
            paragraph('Scene text.'),
      );

      final imported = DocxImporter.parse(bytes);

      expect(imported, hasLength(1));
      expect(imported.first.title, 'Chapter One');
      expect(imported.first.content, contains('Opening line.'));
      expect(imported.first.children.single.title, 'Scene A');
      expect(imported.first.children.single.content, contains('Scene text.'));
    });

    test('a *** paragraph becomes a scene break, not a heading or lost content', () {
      final bytes = buildDocx(
        heading('Heading1', 'Chapter One') +
            paragraph('First half.') +
            paragraph('***') +
            paragraph('Second half.'),
      );

      final imported = DocxImporter.parse(bytes);

      expect(imported.single.content, contains('First half.\n***\nSecond half.'));
    });
  });
}
