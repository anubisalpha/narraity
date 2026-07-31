import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/thesaurus_service.dart';

/// One WordNet database instance app-wide — same "loading is a cheap local
/// file read, not a network fetch, so there's no reason to reload it per
/// scene" rationale as [spellCheckServiceProvider].
final thesaurusServiceProvider = FutureProvider<ThesaurusService>((ref) async {
  final service = await ThesaurusService.load();
  ref.onDispose(service.dispose);
  return service;
});

const thesaurusEnabledPrefKey = 'thesaurus.enabled';

/// Whether the "Look Up" thesaurus popover is offered — mirrors
/// [SpellCheckEnabledNotifier] exactly (same persisted-bool, on-by-default
/// shape, and the same reason it needs a real Notifier instead of a plain
/// StateProvider: app-settings sync needs a real SharedPreferences key to
/// read/write, see `app_settings_service.dart`).
class ThesaurusEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    _restore();
    return true;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(thesaurusEnabledPrefKey) ?? true;
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(thesaurusEnabledPrefKey, enabled);
  }
}

final thesaurusEnabledProvider =
    NotifierProvider<ThesaurusEnabledNotifier, bool>(ThesaurusEnabledNotifier.new);
