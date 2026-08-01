import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'library_service.dart';

/// One entry in `NEWS.md`, parsed from a `## YYYY-MM-DD: Title` heading and
/// the body text under it.
class NewsEntry {
  const NewsEntry({required this.date, required this.title, required this.body});

  final DateTime date;
  final String title;
  final String body;

  Map<String, Object?> toJson() => {
        'date': date.toIso8601String(),
        'title': title,
        'body': body,
      };

  factory NewsEntry.fromJson(Map<String, Object?> json) => NewsEntry(
        date: DateTime.parse(json['date'] as String),
        title: json['title'] as String,
        body: json['body'] as String,
      );
}

/// Fetches `NEWS.md` from the repo's raw content (not the GitHub API — this
/// is just a plain file fetch, no rate-limit-sensitive endpoint) and parses
/// it into dated entries. Distinct from `ReleaseNotesService`: News is
/// free-form and can be updated any time by editing `NEWS.md` directly,
/// independent of cutting an app release.
///
/// Cached to `_Settings/news_cache.json`, same reserved-folder convention as
/// `release_notes_cache.json`/`settings.json`, so the feed has something to
/// show offline.
class NewsService {
  NewsService({http.Client? client, LibraryService? libraryService})
      : _client = client ?? http.Client(),
        _library = libraryService ?? LibraryService();

  final http.Client _client;
  final LibraryService _library;

  static const _newsUrl = 'https://raw.githubusercontent.com/anubisalpha/narraity/main/NEWS.md';

  // Matches "## 2026-08-01: Title" — captures the date and the title text.
  static final _headingPattern = RegExp(r'^##\s+(\d{4}-\d{2}-\d{2}):\s*(.+)$', multiLine: true);

  Future<File> _cacheFile() async {
    final root = await _library.libraryRoot();
    final dir = Directory(p.join(root.path, '_Settings'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, 'news_cache.json'));
  }

  /// Parses raw `NEWS.md` content into entries, newest-first (source order —
  /// the file itself is expected to list newest first, this doesn't re-sort).
  List<NewsEntry> parse(String markdown) {
    final matches = _headingPattern.allMatches(markdown).toList();
    final entries = <NewsEntry>[];

    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      final date = DateTime.tryParse(match.group(1)!);
      if (date == null) continue;

      final bodyStart = match.end;
      final bodyEnd = i + 1 < matches.length ? matches[i + 1].start : markdown.length;
      final body = markdown.substring(bodyStart, bodyEnd).trim();

      entries.add(NewsEntry(date: date, title: match.group(2)!.trim(), body: body));
    }

    return entries;
  }

  Future<List<NewsEntry>> fetchFromGitHub() async {
    final response =
        await _client.get(Uri.parse(_newsUrl)).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('GitHub returned HTTP ${response.statusCode}');
    }

    final entries = parse(response.body);
    await _saveCache(entries);
    return entries;
  }

  Future<void> _saveCache(List<NewsEntry> entries) async {
    final file = await _cacheFile();
    final json = {
      'fetchedAt': DateTime.now().toIso8601String(),
      'entries': entries.map((e) => e.toJson()).toList(),
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }

  Future<(List<NewsEntry> entries, DateTime? fetchedAt)> loadCached() async {
    final file = await _cacheFile();
    if (!await file.exists()) return (<NewsEntry>[], null);

    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final entries = (json['entries'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(NewsEntry.fromJson)
          .toList();
      final fetchedAt = DateTime.tryParse(json['fetchedAt'] as String? ?? '');
      return (entries, fetchedAt);
    } catch (_) {
      return (<NewsEntry>[], null);
    }
  }

  /// Fetches fresh, falling back to the cache on any failure (offline,
  /// GitHub unreachable) — same "nice to have, never block on it" posture as
  /// `ReleaseNotesService.load`.
  Future<(List<NewsEntry> entries, DateTime? fetchedAt, bool fromCache)> load() async {
    try {
      final entries = await fetchFromGitHub();
      return (entries, DateTime.now(), false);
    } catch (_) {
      final (cached, fetchedAt) = await loadCached();
      return (cached, fetchedAt, true);
    }
  }
}
