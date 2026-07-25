import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/annotation.dart';
import 'annotation_service.dart';
import 'manuscript_service.dart';
import 'paragraph_splitter.dart';
import 'review_markdown_parser.dart';

/// AI/external review round-trip (Phase 4): export scenes as stable-anchored
/// Markdown an LLM or human beta reader can comment on, then import their
/// comments back onto the exact right spot.
///
/// **Placement, per PLAN.md:** "extension of the Phase 4 comment/highlight/
/// footnote anchoring system... not a separate phase" — this class does no
/// anchor resolution of its own. It builds a `TextAnchor` per paragraph
/// (same model `AnnotationHighlightController`/`AnnotationService` already
/// use) and creates ordinary `AnnotationKind.comment` annotations on import.
/// Once the scene is next opened, the existing `resolveForScene` self-heals
/// moved paragraphs and flags orphaned ones — reusing that machinery instead
/// of building a separate "nearest paragraph" fallback, since a
/// whole-content substring search is a strictly finer-grained version of the
/// same idea. Deliberate deviation from PLAN.md's literal wording.
///
/// **Anchor persistence:** the export markdown only carries `<!-- id: ... -->`
/// markers — nothing about *what the paragraph looked like* travels with it,
/// since a reviewer's comments-only JSON reply has no reason to echo the
/// prose back. So each export upserts every paragraph's `TextAnchor` into a
/// local `review/anchors.json` store (never sent to the reviewer), and
/// import looks anchor ids up there. Anchors accumulate across exports
/// (keyed by id) rather than one file per export session, so import doesn't
/// need to know which export a reply belongs to.
class ReviewExportService {
  ReviewExportService(this.manuscriptService, this.annotationService);

  final ManuscriptService manuscriptService;
  final AnnotationService annotationService;

  Directory get _reviewDir =>
      Directory(p.join(manuscriptService.projectDir.path, 'review'));
  File get _anchorsFile => File(p.join(_reviewDir.path, 'anchors.json'));

  /// Builds the reviewer-facing Markdown for [scenes] (in the given order)
  /// and merges their paragraph anchors into the persistent store. Leads
  /// with a metadata block — project title/subtitle/author and export
  /// timestamp — so a reviewer opening the file (in the app's own review
  /// screen, or just as raw text) knows whose work and which project this
  /// is, without that block being mistaken for scene content. Then each
  /// scene becomes a `## Title` heading followed by its paragraphs, each
  /// preceded by a `<!-- id: <sceneId>-p<NNN> -->` marker.
  Future<String> buildExportMarkdown(
    List<(String sceneId, String title)> scenes, {
    required String projectTitle,
    String? subtitle,
    String? author,
  }) async {
    final stored = await _loadAnchors();
    final buffer = StringBuffer();

    final metadata = ReviewExportMetadata(
      projectTitle: projectTitle,
      subtitle: subtitle,
      author: author,
      exportedAt: DateTime.now(),
    );
    buffer.writeln('# $projectTitle');
    if (subtitle != null && subtitle.trim().isNotEmpty) {
      buffer.writeln('*$subtitle*');
    }
    if (author != null && author.trim().isNotEmpty) {
      buffer.writeln('**Author:** $author');
    }
    buffer.writeln('**Exported:** ${metadata.exportedAt.toIso8601String()}');
    buffer.writeln();
    buffer.writeln(
      '<!-- narraity-review-export ${jsonEncode(metadata.toJson())} -->',
    );
    buffer.writeln();

    for (final (sceneId, fallbackTitle) in scenes) {
      final doc = await manuscriptService.readScene(
        sceneId,
        fallbackTitle: fallbackTitle,
      );
      buffer.writeln('## ${doc.title}');
      buffer.writeln();

      final paragraphs = splitParagraphs(doc.content);
      for (final paragraph in paragraphs) {
        final id =
            '$sceneId-p${(paragraph.index + 1).toString().padLeft(3, '0')}';
        buffer.writeln('<!-- id: $id -->');
        buffer.writeln(paragraph.text);
        buffer.writeln();
        stored[id] = _StoredAnchor(
          sceneId: sceneId,
          anchor: TextAnchor(
            start: paragraph.start,
            end: paragraph.end,
            quotedText: paragraph.text,
          ),
        );
      }
    }

    await _saveAnchors(stored);
    return buffer.toString();
  }

  /// Parses a reviewer's reply — `{"comments": [{"anchorId", "text",
  /// "category"?}]}` — and creates one in-app comment per entry, anchored
  /// via the stored paragraph anchor. `category` (if present) is prefixed
  /// onto the comment body (`"[pacing] ..."`) rather than given its own
  /// `Annotation` field — a whole model field for one narrow use isn't
  /// worth it when a plain-text prefix reads just as well in the panel.
  ///
  /// Anchor ids the store has never seen (typo, hand-edited JSON, a reply
  /// to an export this project never made) are counted as `unknown` rather
  /// than imported as an unanchored comment — an annotation with no scene to
  /// attach to isn't meaningful.
  Future<ReviewImportResult> importComments(String json) async {
    final stored = await _loadAnchors();
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final comments = (decoded['comments'] as List<dynamic>? ?? []);

    var imported = 0;
    var unknown = 0;

    for (final raw in comments) {
      final map = raw as Map<String, dynamic>;
      final anchorId = map['anchorId'] as String?;
      final entry = anchorId == null ? null : stored[anchorId];
      if (entry == null) {
        unknown++;
        continue;
      }

      final text = map['text'] as String? ?? '';
      final category = (map['category'] as String?)?.trim();
      final body = (category == null || category.isEmpty)
          ? text
          : '[$category] $text';

      await annotationService.create(
        sceneId: entry.sceneId,
        kind: AnnotationKind.comment,
        anchor: entry.anchor,
        body: body,
      );
      imported++;
    }

    return ReviewImportResult(imported: imported, unknown: unknown);
  }

  Future<Map<String, _StoredAnchor>> _loadAnchors() async {
    if (!await _anchorsFile.exists()) return {};
    try {
      final json =
          jsonDecode(await _anchorsFile.readAsString()) as Map<String, dynamic>;
      final anchors = json['anchors'] as Map<String, dynamic>? ?? {};
      return anchors.map(
        (id, value) =>
            MapEntry(id, _StoredAnchor.fromJson(value as Map<String, dynamic>)),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveAnchors(Map<String, _StoredAnchor> anchors) async {
    await _reviewDir.create(recursive: true);
    await _anchorsFile.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'anchors': anchors.map((id, a) => MapEntry(id, a.toJson()))}),
    );
  }
}

class ReviewImportResult {
  const ReviewImportResult({required this.imported, required this.unknown});

  final int imported;
  final int unknown;
}

class _StoredAnchor {
  const _StoredAnchor({required this.sceneId, required this.anchor});

  final String sceneId;
  final TextAnchor anchor;

  Map<String, dynamic> toJson() => {
    'sceneId': sceneId,
    'anchor': anchor.toJson(),
  };

  factory _StoredAnchor.fromJson(Map<String, dynamic> json) => _StoredAnchor(
    sceneId: json['sceneId'] as String,
    anchor: TextAnchor.fromJson(json['anchor'] as Map<String, dynamic>),
  );
}
