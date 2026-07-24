import 'package:flutter/material.dart';

import '../models/manuscript_seeds.dart';

class NewProjectResult {
  final String title;
  final String? author;
  final ManuscriptSeed seed;

  const NewProjectResult({required this.title, this.author, required this.seed});
}

Future<NewProjectResult?> showNewProjectDialog(BuildContext context) {
  final titleController = TextEditingController();
  final authorController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  var seed = ManuscriptSeed.actChapterScene;

  return showDialog<NewProjectResult>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New Project'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: titleController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Title is required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: authorController,
                    decoration: const InputDecoration(labelText: 'Author (optional)'),
                  ),
                  const SizedBox(height: 16),
                  Text('Manuscript structure', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Just a starting point — you can add and label sections however you '
                    'like at any time.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ManuscriptSeed>(
                    initialValue: seed,
                    isExpanded: true,
                    items: [
                      for (final option in ManuscriptSeed.values)
                        DropdownMenuItem(value: option, child: Text(option.label)),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => seed = value);
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(seed.description, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.of(context).pop(
                  NewProjectResult(
                    title: titleController.text.trim(),
                    author: authorController.text.trim().isEmpty
                        ? null
                        : authorController.text.trim(),
                    seed: seed,
                  ),
                );
              },
              child: const Text('Create'),
            ),
          ],
        ),
      );
    },
  );
}
