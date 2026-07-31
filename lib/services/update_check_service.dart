import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown when the GitHub Releases API can't be reached or returns something
/// unexpected — distinct from "checked successfully, no update available"
/// (which is just a null result), so the UI can tell the two apart.
class UpdateCheckException implements Exception {
  UpdateCheckException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A release newer than the currently running build.
class UpdateInfo {
  const UpdateInfo({required this.version, required this.htmlUrl, required this.notes});

  final String version;
  final String htmlUrl;
  final String notes;
}

/// Checks GitHub's "latest release" API for the published repo and compares
/// its tag against the running app's version. There's no silent
/// auto-installer here — Narraity ships as a signed MSIX the user installs
/// by hand, so this only ever points them at the release page to download it
/// themselves.
class UpdateCheckService {
  UpdateCheckService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _releasesUrl =
      'https://api.github.com/repos/anubisalpha/narraity/releases/latest';

  Future<UpdateInfo?> checkForUpdate(String currentVersion) async {
    final http.Response response;
    try {
      response = await _client
          .get(Uri.parse(_releasesUrl), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));
    } catch (error) {
      throw UpdateCheckException('Could not reach GitHub: $error');
    }

    if (response.statusCode != 200) {
      throw UpdateCheckException('GitHub returned HTTP ${response.statusCode}');
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (error) {
      throw UpdateCheckException('Unexpected response from GitHub: $error');
    }

    final tag = (json['tag_name'] as String? ?? '').trim();
    final latestVersion = tag.startsWith('v') ? tag.substring(1) : tag;
    if (latestVersion.isEmpty) {
      throw UpdateCheckException('Latest release has no tag_name');
    }

    if (!_isNewer(latestVersion, currentVersion)) return null;

    return UpdateInfo(
      version: latestVersion,
      htmlUrl: json['html_url'] as String? ??
          'https://github.com/anubisalpha/narraity/releases/latest',
      notes: (json['body'] as String? ?? '').trim(),
    );
  }

  /// Compares dotted numeric versions (`1.2.10` vs `1.3.0`), ignoring any
  /// `+build` suffix — that's Android's versionCode, not a user-facing
  /// version, and isn't part of a GitHub tag anyway.
  bool _isNewer(String candidate, String current) {
    final a = _parse(candidate);
    final b = _parse(current);
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  List<int> _parse(String version) {
    final parts = version.split('+').first.split('.');
    return List.generate(3, (i) => i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0);
  }
}
