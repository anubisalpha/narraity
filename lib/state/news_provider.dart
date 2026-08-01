import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/news_service.dart';

final newsServiceProvider = Provider<NewsService>((ref) => NewsService());

/// One fetch-or-fall-back-to-cache per app session, same rationale as
/// `releaseNotesProvider`/`updateCheckProvider`.
final newsProvider = FutureProvider<(List<NewsEntry>, DateTime?, bool)>((ref) {
  return ref.read(newsServiceProvider).load();
});
