import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/ideas_provider.dart';

/// Global "New Idea" quick-capture — minimal friction, available anywhere in
/// the app (library and inside a project). Title required, body and tags
/// optional; tags are comma-separated free text.
Future<void> showQuickCaptureDialog(BuildContext context, WidgetRef ref) async {
  final titleController = TextEditingController();
  final bodyController = TextEditingController();
  final tagsController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final captured = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('New Idea'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Idea'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'An idea needs a title' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: bodyController,
                  decoration: const InputDecoration(
                    labelText: 'Details (optional)',
                    alignLabelWithHint: true,
                  ),
                  minLines: 3,
                  maxLines: 6,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: tagsController,
                  decoration: const InputDecoration(
                    labelText: 'Tags (optional, comma-separated)',
                    hintText: 'character, plot twist, title…',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(context).pop(true);
            },
            child: const Text('Capture'),
          ),
        ],
      );
    },
  );

  if (captured != true) return;

  final tags = tagsController.text
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  await ref.read(ideasServiceProvider).captureIdea(
        title: titleController.text.trim(),
        body: bodyController.text.trim(),
        tags: tags,
      );
  ref.invalidate(ideaListProvider);
}
