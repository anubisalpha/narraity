import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Editing-view typography — a curated set of comfortable writing fonts,
/// separate from export fonts (PLAN.md "Editing-view fonts"). Persisted
/// app-wide, not per project.
class EditorSettings {
  final String fontFamily;
  final double fontSize;
  final double lineHeight;

  const EditorSettings({
    this.fontFamily = 'Georgia',
    this.fontSize = 16,
    this.lineHeight = 1.6,
  });

  static const availableFonts = ['Georgia', 'Times New Roman', 'Segoe UI', 'Consolas'];

  EditorSettings copyWith({String? fontFamily, double? fontSize, double? lineHeight}) =>
      EditorSettings(
        fontFamily: fontFamily ?? this.fontFamily,
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
      );
}

class EditorSettingsNotifier extends Notifier<EditorSettings> {
  @override
  EditorSettings build() {
    _restore();
    return const EditorSettings();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = EditorSettings(
      fontFamily: prefs.getString('editor.fontFamily') ?? 'Georgia',
      fontSize: prefs.getDouble('editor.fontSize') ?? 16,
      lineHeight: prefs.getDouble('editor.lineHeight') ?? 1.6,
    );
  }

  Future<void> update(EditorSettings settings) async {
    state = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('editor.fontFamily', settings.fontFamily);
    await prefs.setDouble('editor.fontSize', settings.fontSize);
    await prefs.setDouble('editor.lineHeight', settings.lineHeight);
  }
}

final editorSettingsProvider =
    NotifierProvider<EditorSettingsNotifier, EditorSettings>(EditorSettingsNotifier.new);
