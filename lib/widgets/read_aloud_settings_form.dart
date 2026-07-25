import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/tts_service.dart';
import '../state/tts_provider.dart';
import '../state/tts_settings_provider.dart';

/// Voice/rate/pitch controls for Read Aloud — Settings > Read Aloud.
class ReadAloudSettingsForm extends ConsumerWidget {
  const ReadAloudSettingsForm({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(ttsSettingsProvider);
    final notifier = ref.read(ttsSettingsProvider.notifier);
    final voicesAsync = ref.watch(availableTtsVoicesProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        voicesAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (err, _) => Text('Could not list voices: $err'),
          data: (voices) => DropdownButtonFormField<TtsVoice?>(
            initialValue: settings.voice,
            decoration: const InputDecoration(labelText: 'Voice'),
            items: [
              const DropdownMenuItem(value: null, child: Text('System default')),
              for (final voice in voices)
                DropdownMenuItem(
                  value: voice,
                  child: Text(
                    voice.locale.isEmpty ? voice.name : '${voice.name} (${voice.locale})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (voice) => notifier.update(settings.copyWith(voice: voice)),
          ),
        ),
        const SizedBox(height: 16),
        Text('Speed: ${settings.rate.toStringAsFixed(2)}'),
        Slider(
          value: settings.rate,
          min: 0.1,
          max: 1.0,
          divisions: 18,
          onChanged: (rate) => notifier.update(settings.copyWith(rate: rate)),
        ),
        Text('Pitch: ${settings.pitch.toStringAsFixed(2)}'),
        Slider(
          value: settings.pitch,
          min: 0.5,
          max: 2.0,
          divisions: 15,
          onChanged: (pitch) => notifier.update(settings.copyWith(pitch: pitch)),
        ),
      ],
    );
  }
}
