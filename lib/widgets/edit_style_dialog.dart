import 'package:flutter/material.dart';

import '../models/project.dart';
import 'project_kind_style.dart';

/// Lets a user change an existing project's card style after creation —
/// reuses the same [SegmentedButton] picker as the New Project dialog, just
/// without the title/author/manuscript-structure fields that only make
/// sense at creation time.
Future<ProjectKind?> showEditStyleDialog(BuildContext context, ProjectKind current) {
  var kind = current;

  return showDialog<ProjectKind>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Card style'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Purely visual — how this project\'s library card looks. Doesn\'t change how '
                  'you write or export.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
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
                  onSelectionChanged: (selection) => setState(() => kind = selection.first),
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
              onPressed: () => Navigator.of(context).pop(kind),
              child: const Text('Save'),
            ),
          ],
        ),
      );
    },
  );
}
