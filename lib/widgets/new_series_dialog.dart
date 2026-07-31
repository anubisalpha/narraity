import 'package:flutter/material.dart';

Future<String?> showNewSeriesDialog(BuildContext context) {
  final titleController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('New Series'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: formKey,
          child: TextFormField(
            controller: titleController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Series title',
              hintText: 'e.g. Wisdom of the Elders',
            ),
            validator: (value) =>
                (value == null || value.trim().isEmpty) ? 'Title is required' : null,
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
            Navigator.of(context).pop(titleController.text.trim());
          },
          child: const Text('Create'),
        ),
      ],
    ),
  );
}
