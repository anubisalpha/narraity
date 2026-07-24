import 'package:flutter/material.dart';

class NewProjectResult {
  final String title;
  final String? author;

  const NewProjectResult({required this.title, this.author});
}

Future<NewProjectResult?> showNewProjectDialog(BuildContext context) {
  final titleController = TextEditingController();
  final authorController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  return showDialog<NewProjectResult>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('New Project'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
            ],
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
                ),
              );
            },
            child: const Text('Create'),
          ),
        ],
      );
    },
  );
}
