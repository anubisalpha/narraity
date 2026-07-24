import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/editor_settings_provider.dart';

/// The editing-view typography controls (font/size/line-spacing) — shared
/// between the in-editor quick dialog and the Settings > Editor page so the
/// two stay in sync without duplicating logic.
class EditorSettingsForm extends ConsumerWidget {
  const EditorSettingsForm({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(editorSettingsProvider);
    final notifier = ref.read(editorSettingsProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: settings.fontFamily,
          decoration: const InputDecoration(labelText: 'Writing font'),
          items: [
            for (final font in EditorSettings.availableFonts)
              DropdownMenuItem(
                value: font,
                child: Text(font, style: TextStyle(fontFamily: font)),
              ),
          ],
          onChanged: (font) {
            if (font != null) {
              notifier.update(settings.copyWith(fontFamily: font));
            }
          },
        ),
        const SizedBox(height: 16),
        Text('Font size: ${settings.fontSize.round()}'),
        Slider(
          value: settings.fontSize,
          min: 12,
          max: 24,
          divisions: 12,
          onChanged: (size) => notifier.update(settings.copyWith(fontSize: size)),
        ),
        Text('Line spacing: ${settings.lineHeight.toStringAsFixed(1)}'),
        Slider(
          value: settings.lineHeight,
          min: 1.0,
          max: 2.5,
          divisions: 15,
          onChanged: (height) => notifier.update(settings.copyWith(lineHeight: height)),
        ),
      ],
    );
  }
}
