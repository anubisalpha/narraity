import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/tts_service.dart';

/// Read Aloud voice/rate/pitch, persisted app-wide (not per project) — same
/// convention as `EditorSettings`. Null [voiceName]/[voiceLocale] means "use
/// whatever the platform defaults to."
class TtsSettings {
  const TtsSettings({
    this.rate = 0.5,
    this.pitch = 1.0,
    this.voiceName,
    this.voiceLocale,
  });

  /// 0.0-1.0, `flutter_tts`'s own normalized scale (not words-per-minute).
  final double rate;
  final double pitch;
  final String? voiceName;
  final String? voiceLocale;

  TtsVoice? get voice =>
      voiceName == null ? null : TtsVoice(name: voiceName!, locale: voiceLocale ?? '');

  TtsSettings copyWith({double? rate, double? pitch, TtsVoice? voice}) => TtsSettings(
        rate: rate ?? this.rate,
        pitch: pitch ?? this.pitch,
        voiceName: voice?.name ?? voiceName,
        voiceLocale: voice?.locale ?? voiceLocale,
      );
}

class TtsSettingsNotifier extends Notifier<TtsSettings> {
  @override
  TtsSettings build() {
    _restore();
    return const TtsSettings();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = TtsSettings(
      rate: prefs.getDouble('tts.rate') ?? 0.5,
      pitch: prefs.getDouble('tts.pitch') ?? 1.0,
      voiceName: prefs.getString('tts.voiceName'),
      voiceLocale: prefs.getString('tts.voiceLocale'),
    );
  }

  Future<void> update(TtsSettings settings) async {
    state = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('tts.rate', settings.rate);
    await prefs.setDouble('tts.pitch', settings.pitch);
    if (settings.voiceName == null) {
      await prefs.remove('tts.voiceName');
      await prefs.remove('tts.voiceLocale');
    } else {
      await prefs.setString('tts.voiceName', settings.voiceName!);
      await prefs.setString('tts.voiceLocale', settings.voiceLocale ?? '');
    }
  }
}

final ttsSettingsProvider =
    NotifierProvider<TtsSettingsNotifier, TtsSettings>(TtsSettingsNotifier.new);
