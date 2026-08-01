import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'library_service.dart';

/// One published GitHub release.
class ReleaseNote {
  const ReleaseNote({
    required this.version,
    required this.notes,
    required this.htmlUrl,
    required this.publishedAt,
  });

  final String version;
  final String notes;
  final String htmlUrl;
  final DateTime? publishedAt;

  Map<String, Object?> toJson() => {
        'version': version,
        'notes': notes,
        'htmlUrl': htmlUrl,
        'publishedAt': publishedAt?.toIso8601String(),
      };

  factory ReleaseNote.fromJson(Map<String, Object?> json) => ReleaseNote(
        version: json['version'] as String,
        notes: json['notes'] as String,
        htmlUrl: json['htmlUrl'] as String,
        publishedAt: (json['publishedAt'] as String?) == null
            ? null
            : DateTime.tryParse(json['publishedAt'] as String),
      );
}

/// Fetches the full published-release history from GitHub (unlike
/// `UpdateCheckService`, which only looks at `/releases/latest` to decide
/// whether an update banner is warranted) so a "Release Notes" screen can
/// show more than just the newest version. Same public, unauthenticated
/// GitHub REST endpoint family as `UpdateCheckService` — no new network
/// surface, just a different endpoint on the same API.
///
/// Cached to `_Settings/release_notes_cache.json` (same reserved-folder
/// convention as `custom-words-*.txt`/`settings.json`) so the Release Notes
/// screen has something to show offline, stamped with a fetch timestamp.
class ReleaseNotesService {
  ReleaseNotesService({http.Client? client, LibraryService? libraryService})
      : _client = client ?? http.Client(),
        _library = libraryService ?? LibraryService();

  final http.Client _client;
  final LibraryService _library;

  static const _releasesUrl = 'https://api.github.com/repos/anubisalpha/narraity/releases';

  Future<File> _cacheFile() async {
    final root = await _library.libraryRoot();
    final dir = Directory(p.join(root.path, '_Settings'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, 'release_notes_cache.json'));
  }

  /// Releases most-recent-first, freshly fetched from GitHub. Throws on any
  /// network/parse failure — callers that want an offline fallback should
  /// catch and fall back to [loadCached].
  Future<List<ReleaseNote>> fetchFromGitHub() async {
    final response = await _client
        .get(Uri.parse(_releasesUrl), headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('GitHub returned HTTP ${response.statusCode}');
    }

    final list = jsonDecode(response.body) as List<Object?>;
    final releases = list
        .cast<Map<String, Object?>>()
        .where((r) => r['draft'] != true) // pre-releases are shown; drafts are never public
        .map((r) {
      final tag = (r['tag_name'] as String? ?? '').trim();
      return ReleaseNote(
        version: tag.startsWith('v') ? tag.substring(1) : tag,
        notes: (r['body'] as String? ?? '').trim(),
        htmlUrl: r['html_url'] as String? ?? '',
        publishedAt: DateTime.tryParse(r['published_at'] as String? ?? ''),
      );
    }).toList();

    await _saveCache(releases);
    return releases;
  }

  Future<void> _saveCache(List<ReleaseNote> releases) async {
    final file = await _cacheFile();
    final json = {
      'fetchedAt': DateTime.now().toIso8601String(),
      'releases': releases.map((r) => r.toJson()).toList(),
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }

  /// The last successfully cached list, or `[]` if nothing's been fetched
  /// yet on this device. Also returns the cache's fetch timestamp, so the UI
  /// can show "last updated ..." when serving stale/offline data.
  Future<(List<ReleaseNote> releases, DateTime? fetchedAt)> loadCached() async {
    final file = await _cacheFile();
    if (!await file.exists()) return (<ReleaseNote>[], null);

    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final releases = (json['releases'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(ReleaseNote.fromJson)
          .toList();
      final fetchedAt = DateTime.tryParse(json['fetchedAt'] as String? ?? '');
      return (releases, fetchedAt);
    } catch (_) {
      // Corrupt/unreadable cache — treat as empty rather than crashing the
      // Release Notes screen over a local file problem.
      return (<ReleaseNote>[], null);
    }
  }

  /// Fetches fresh data, falling back to the cache on any failure (offline,
  /// GitHub down, rate-limited) rather than surfacing an error for a screen
  /// that's fundamentally "nice to have."
  Future<(List<ReleaseNote> releases, DateTime? fetchedAt, bool fromCache)> load() async {
    try {
      final releases = await fetchFromGitHub();
      return (releases, DateTime.now(), false);
    } catch (_) {
      final (cached, fetchedAt) = await loadCached();
      return (cached, fetchedAt, true);
    }
  }
}
