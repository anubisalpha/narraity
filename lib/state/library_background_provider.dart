import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/library_background.dart';

const _libraryBackgroundPrefKey = 'libraryBackground';

/// Persists the user's Library screen background choice — an *extra*
/// option alongside the light/dark/system theme selector (see
/// `theme_provider.dart`), not a replacement for it: the theme still
/// governs everything else (card colors, text, app bar); this only affects
/// the backdrop behind the grid. Defaults to [ThemeDefaultBackground] (no
/// custom background at all) for anyone who's never touched this setting.
class LibraryBackgroundNotifier extends Notifier<LibraryBackgroundChoice> {
  @override
  LibraryBackgroundChoice build() {
    _restore();
    return const ThemeDefaultBackground();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_libraryBackgroundPrefKey);
    if (savedId == null) return;
    state = libraryBackgroundChoiceById(savedId);
  }

  Future<void> select(LibraryBackgroundChoice choice) async {
    state = choice;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_libraryBackgroundPrefKey, choice.id);
  }
}

final libraryBackgroundProvider =
    NotifierProvider<LibraryBackgroundNotifier, LibraryBackgroundChoice>(
      LibraryBackgroundNotifier.new,
    );
