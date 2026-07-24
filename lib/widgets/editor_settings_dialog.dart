import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/editor_settings_provider.dart';

/// Editing-view typography settings — curated font list, size, line spacing.
Future<void> showEditorSettingsDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final settings = ref.watch(editorSettingsProvider);
        final notifier = ref.read(editorSettingsProvider.notifier);

        return AlertDialog(
          title: const Text('Editor Settings'),
          content: SizedBox(
            width: 360,
            child: Column(
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
                  onChanged: (size) =>
                      notifier.update(settings.copyWith(fontSize: size)),
                ),
                Text('Line spacing: ${settings.lineHeight.toStringAsFixed(1)}'),
                Slider(
                  value: settings.lineHeight,
                  min: 1.0,
                  max: 2.5,
                  divisions: 15,
                  onChanged: (height) =>
                      notifier.update(settings.copyWith(lineHeight: height)),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    ),
  );
}
