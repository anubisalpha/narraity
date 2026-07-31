import 'package:flutter/material.dart';

import '../models/project.dart';

/// Where imported content should land — chosen once, up front, before any
/// parsing result gets written to disk.
sealed class ImportDestination {
  const ImportDestination();
}

class ImportAsNewProject extends ImportDestination {
  const ImportAsNewProject({required this.title, this.author});
  final String title;
  final String? author;
}

class ImportReplacingProject extends ImportDestination {
  const ImportReplacingProject(this.project);
  final Project project;
}

/// Asks where an already-parsed import should go: a brand-new project, or
/// replacing an existing one's manuscript content entirely. Replacing is
/// the destructive path — this dialog only captures the choice; the
/// double-confirmation warning for it lives in the caller
/// (`library_screen.dart`), shown as two separate dialogs afterward so the
/// destructive step is never bundled into a single click with the
/// destination choice itself.
Future<ImportDestination?> showImportDestinationDialog(
  BuildContext context, {
  required List<Project> existingProjects,
  required String suggestedTitle,
}) {
  final titleController = TextEditingController(text: suggestedTitle);
  final authorController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  var replacing = false;
  Project? selectedProject = existingProjects.isEmpty ? null : existingProjects.first;

  return showDialog<ImportDestination>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Import Manuscript'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: RadioGroup<bool>(
                groupValue: replacing,
                onChanged: (value) => setState(() => replacing = value!),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Create a new project'),
                      value: false,
                    ),
                    if (!replacing) ...[
                      TextFormField(
                        controller: titleController,
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
                    const SizedBox(height: 8),
                    RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Replace an existing project'),
                      subtitle: existingProjects.isEmpty
                          ? const Text('No projects to replace yet.')
                          : const Text('Permanently deletes that project\'s current manuscript.'),
                      value: true,
                      enabled: existingProjects.isNotEmpty,
                    ),
                    if (replacing) ...[
                      DropdownButtonFormField<Project>(
                        initialValue: selectedProject,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Project to replace'),
                        items: [
                          for (final project in existingProjects)
                            DropdownMenuItem(value: project, child: Text(project.title)),
                        ],
                        onChanged: (value) => setState(() => selectedProject = value),
                      ),
                    ],
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
                if (replacing) {
                  if (selectedProject == null) return;
                  Navigator.of(context).pop(ImportReplacingProject(selectedProject!));
                  return;
                }
                if (!formKey.currentState!.validate()) return;
                Navigator.of(context).pop(ImportAsNewProject(
                  title: titleController.text.trim(),
                  author: authorController.text.trim().isEmpty
                      ? null
                      : authorController.text.trim(),
                ));
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    },
  );
}
