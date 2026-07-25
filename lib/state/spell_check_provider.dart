import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/spell_check_service.dart';

/// en-GB only for now (PLAN.md's default) — the per-project language/variant
/// picker and additional downloadable dictionaries are a follow-up, not
/// built this session. One dictionary instance app-wide (loading is a cheap
/// local file read+parse, not a network fetch, so there's no reason to
/// reload it per scene).
final spellCheckServiceProvider = FutureProvider<SpellCheckService>((ref) async {
  final service = await SpellCheckService.load('en_GB');
  ref.onDispose(service.dispose);
  return service;
});

/// Whether spell check is switched on — a plain toggle, not per-project
/// settings (matches the "on by default, one Settings flag" shape until
/// there's a reason for anything fancier).
final spellCheckEnabledProvider = StateProvider<bool>((ref) => true);
