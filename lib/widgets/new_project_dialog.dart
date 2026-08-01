import 'package:flutter/material.dart';

import '../models/manuscript_seeds.dart';
import '../models/project.dart';
import 'project_kind_style.dart';

class NewProjectResult {
  final String title;
  final String? author;
  final ManuscriptSeed seed;
  final ProjectKind kind;

  const NewProjectResult({
    required this.title,
    this.author,
    required this.seed,
    this.kind = ProjectKind.novel,
  });
}

Future<NewProjectResult?> showNewProjectDialog(BuildContext context) {
  final titleController = TextEditingController();
  final authorController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  var seed = ManuscriptSeed.actChapterScene;
  var kind = ProjectKind.novel;

  return showDialog<NewProjectResult>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New Project'),
          content: SizedBox(
            width: 420,
            // Scrollable rather than a bare Column: AlertDialog constrains
            // content height, and adding the card-style picker below made
            // the natural content taller than that constraint on smaller
            // windows — an unscrollable Column just overflows silently
            // instead of ever letting the user reach the cut-off fields.
            child: SingleChildScrollView(
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
                          (value == null || value.trim().isEmpty)
                          ? 'Title is required'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: authorController,
                      decoration: const InputDecoration(
                        labelText: 'Author (optional)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Card style',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Purely visual — how this project\'s library card looks. Doesn\'t change '
                      'how you write or export.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<ProjectKind>(
                      segments: [
                        for (final option in ProjectKind.values)
                          ButtonSegment(
                            value: option,
                            label: Text(ProjectKindStyle.of(option).label),
                            icon: Icon(ProjectKindStyle.of(option).icon),
                          ),
                      ],
                      selected: {kind},
                      onSelectionChanged: (selection) =>
                          setState(() => kind = selection.first),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Manuscript structure',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
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
                          DropdownMenuItem(
                            value: option,
                            child: Text(option.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => seed = value);
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      seed.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
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
                    kind: kind,
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
