import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/review_session.dart';
import '../services/review_session_service.dart';
import 'library_provider.dart';

final reviewSessionServiceProvider = Provider<ReviewSessionService>(
  (ref) => ReviewSessionService(ref.watch(libraryServiceProvider)),
);

/// All saved review sessions, most recently modified first. Invalidate
/// after creating a session or saving a comment change.
final reviewSessionListProvider = FutureProvider<List<ReviewSession>>((ref) async {
  final service = ref.watch(reviewSessionServiceProvider);
  return service.listSessions();
});
