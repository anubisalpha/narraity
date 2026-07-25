import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/review_session.dart';
import 'library_service.dart';
import 'review_markdown_parser.dart';

const _uuid = Uuid();

/// Reads/writes `_ReviewSessions/` at the library root — one
/// `review-<id>.json` per session, alongside (not inside) project folders,
/// same "works without any project open" convention as `IdeasService`'s
/// `_GlobalIdeas/`. This is the reviewer's own persistent record of a pass
/// through an exported file, independent of the author's project.
class ReviewSessionService {
  ReviewSessionService(this._library);

  final LibraryService _library;

  Future<Directory> _sessionsDir() async {
    final root = await _library.libraryRoot();
    final dir = Directory(p.join(root.path, '_ReviewSessions'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<ReviewSession>> listSessions() async {
    final dir = await _sessionsDir();
    final sessions = <ReviewSession>[];

    await for (final entity in dir.list()) {
      if (entity is! File || !p.basename(entity.path).endsWith('.json')) {
        continue;
      }
      try {
        final json =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        sessions.add(ReviewSession.fromJson(json));
      } catch (_) {
        continue; // skip corrupt files rather than breaking the list view
      }
    }

    sessions.sort((a, b) => b.modified.compareTo(a.modified));
    return sessions;
  }

  /// Starts a new session from an exported review Markdown file's contents.
  /// [fallbackTitle] (typically the filename) is only used when the file has
  /// no metadata comment — the project's real title, if present, is a more
  /// meaningful default.
  Future<ReviewSession> createFromMarkdown(
    String fallbackTitle,
    String markdown,
  ) async {
    final metadata = parseReviewMetadata(markdown);
    final session = ReviewSession(
      id: _uuid.v4(),
      title: metadata?.projectTitle ?? fallbackTitle,
      paragraphs: parseReviewMarkdown(markdown),
      metadata: metadata,
      created: DateTime.now(),
    );
    await save(session);
    return session;
  }

  Future<void> save(ReviewSession session) async {
    session.modified = DateTime.now();
    final dir = await _sessionsDir();
    final file = File(p.join(dir.path, 'review-${session.id}.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(session.toJson()),
    );
  }

  Future<void> deleteSession(ReviewSession session) async {
    final dir = await _sessionsDir();
    final file = File(p.join(dir.path, 'review-${session.id}.json'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Encodes this session's comments into the exact JSON
  /// `ReviewExportService.importComments` (the author's side) expects.
  String exportCommentsJson(ReviewSession session) =>
      encodeReviewComments(session.comments.values.toList());
}
