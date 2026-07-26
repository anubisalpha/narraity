import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

const spellCheckEnabledPrefKey = 'spellCheck.enabled';

/// Whether spell check is switched on — a plain toggle, not per-project
/// settings (matches the "on by default, one Settings flag" shape until
/// there's a reason for anything fancier). Persisted — previously a plain
/// `StateProvider` that reset to "on" every launch; needed real persistence
/// anyway, and Phase 5's app-settings sync needs a real key to read/write.
class SpellCheckEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    _restore();
    return true;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(spellCheckEnabledPrefKey) ?? true;
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(spellCheckEnabledPrefKey, enabled);
  }
}

final spellCheckEnabledProvider =
    NotifierProvider<SpellCheckEnabledNotifier, bool>(SpellCheckEnabledNotifier.new);
