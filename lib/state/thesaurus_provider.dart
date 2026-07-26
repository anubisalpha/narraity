import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/thesaurus_service.dart';

/// One WordNet database instance app-wide — same "loading is a cheap local
/// file read, not a network fetch, so there's no reason to reload it per
/// scene" rationale as [spellCheckServiceProvider].
final thesaurusServiceProvider = FutureProvider<ThesaurusService>((ref) async {
  final service = await ThesaurusService.load();
  ref.onDispose(service.dispose);
  return service;
});
