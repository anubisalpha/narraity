import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../models/manuscript.dart';
import '../../models/manuscript_import.dart';
import '../manuscript_service.dart';
import 'dabble_json_importer.dart';
import 'docx_importer.dart';
import 'plain_text_importer.dart';

const _uuid = Uuid();

/// The file extensions the importer currently understands.
const supportedImportExtensions = ['docx', 'txt', 'md', 'json'];

/// Entry point for turning an external manuscript file into Narraity's own
/// structure/scene format. Parsing (this file's `parseFile`) and writing
/// (`materializeInto`) are kept separate so the caller can show the user
/// what was found — node count, a title preview — before committing
/// anything to disk, especially important for the "replace an existing
/// project" path.
class ManuscriptImporter {
  Future<List<ImportedNode>> parseFile(String path) async {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    final file = File(path);
    switch (ext) {
      case 'docx':
        return DocxImporter.parse(await file.readAsBytes());
      case 'txt':
      case 'md':
        return PlainTextImporter.parse(await file.readAsString());
      case 'json':
        return DabbleJsonImporter.parse(await file.readAsString());
      default:
        throw UnsupportedImportFormatException(ext);
    }
  }

  /// A reasonable pre-filled title for the "new project" destination.
  /// Dabble exports have no project-level title field at all (verified
  /// against real exports) — only the filename, or a single book's own
  /// title when there's exactly one. A one-book import uses that book's
  /// title directly since it's more meaningful than the export filename
  /// (which includes an export timestamp suffix); anything else falls back
  /// to a cleaned-up version of the filename.
  String suggestedTitle(String path, List<ImportedNode> importedNodes) {
    if (p.extension(path).toLowerCase() == '.json' && importedNodes.length == 1) {
      return importedNodes.single.title;
    }
    final name = p.basenameWithoutExtension(path);
    final withoutExportTimestamp = name.replaceFirst(RegExp(r'-\d{4}-\d{2}-\d{2}T[\d\-]+Z$'), '');
    return withoutExportTimestamp.replaceAll('_', ' ').trim();
  }

  /// Writes [importedNodes] as [service]'s entire manuscript structure,
  /// generating fresh stable ids for every node. Does **not** clear any
  /// existing structure first — callers replacing an existing project's
  /// content must call [clearExistingManuscript] first (see
  /// `import_manuscript_dialog.dart`'s double-confirmation flow).
  Future<void> materializeInto(ManuscriptService service, List<ImportedNode> importedNodes) async {
    ManuscriptNode convert(ImportedNode imported) => ManuscriptNode(
          id: '${imported.typeLabel.toLowerCase()}-${_uuid.v4()}',
          title: imported.title,
          typeLabel: imported.typeLabel,
          children: imported.children.map(convert).toList(),
        );

    final builtNodes = importedNodes.map(convert).toList();
    await service.saveStructure(ManuscriptStructure(nodes: builtNodes));

    Future<void> writeContent(ImportedNode imported, ManuscriptNode built) async {
      await service.writeScene(
        SceneDoc(id: built.id, title: built.title, content: imported.content),
      );
      for (var i = 0; i < imported.children.length; i++) {
        await writeContent(imported.children[i], built.children[i]);
      }
    }

    for (var i = 0; i < importedNodes.length; i++) {
      await writeContent(importedNodes[i], builtNodes[i]);
    }
  }

  /// Deletes every existing node's scene file (cascading to its
  /// annotations, same as `ManuscriptService.deleteNode`) ahead of an
  /// import that replaces a project's content — irreversible, so the UI
  /// layer is expected to have already confirmed this with the user twice.
  Future<void> clearExistingManuscript(ManuscriptService service) async {
    final structure = await service.loadStructure();
    for (final id in structure.allContentIds) {
      await service.deleteSceneFile(id);
    }
  }

  /// Rough counts for a pre-import summary — total nodes and an estimated
  /// word count (splitting on whitespace, same measure `SceneDoc.wordCount`
  /// uses) across every node's own content.
  ({int nodeCount, int wordCount}) summarize(List<ImportedNode> nodes) {
    var nodeCount = 0;
    var wordCount = 0;
    void walk(ImportedNode node) {
      nodeCount++;
      final trimmed = node.content.trim();
      if (trimmed.isNotEmpty) {
        wordCount += trimmed.split(RegExp(r'\s+')).length;
      }
      node.children.forEach(walk);
    }

    nodes.forEach(walk);
    return (nodeCount: nodeCount, wordCount: wordCount);
  }
}
