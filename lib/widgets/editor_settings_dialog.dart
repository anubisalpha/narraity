import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'editor_settings_form.dart';

/// Quick in-context access to editor typography while writing — same
/// controls as Settings > Editor (see editor_settings_form.dart), just
/// reachable without leaving the manuscript.
Future<void> showEditorSettingsDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Editor Settings'),
      content: const SizedBox(width: 360, child: EditorSettingsForm()),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
