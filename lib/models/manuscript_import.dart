/// One node parsed out of an imported document, before it's been assigned a
/// stable id and written to disk — mirrors [ManuscriptNode]'s "holds its own
/// prose *and* can have children" shape (see manuscript.dart), just without
/// persistence concerns yet. [content] is already in Narraity's own
/// markdown-lite dialect (`**bold**`, `*italic*`, `~~strike~~`, `***` scene
/// break) regardless of which source format it came from, so
/// `ManuscriptImporter.materializeInto` can treat every source the same way.
class ImportedNode {
  ImportedNode({
    required this.title,
    required this.typeLabel,
    this.content = '',
    List<ImportedNode>? children,
  }) : children = children ?? [];

  String title;
  String typeLabel;
  String content;
  final List<ImportedNode> children;
}

/// Thrown when a file's extension isn't one of the formats the importer
/// understands.
class UnsupportedImportFormatException implements Exception {
  UnsupportedImportFormatException(this.extension);
  final String extension;

  @override
  String toString() => 'Unsupported file type for import: "$extension"';
}

/// Thrown when a file claims to be one of the supported formats but can't
/// actually be parsed as one (corrupt zip, missing document.xml, etc).
class ImportParseException implements Exception {
  ImportParseException(this.message);
  final String message;

  @override
  String toString() => message;
}
