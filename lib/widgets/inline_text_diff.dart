import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';

/// Inline character-level diff of [from] → [to], rendered as selectable text:
/// insertions highlighted green, deletions struck through in red, unchanged
/// text left plain. Shared by the Version History diff pane
/// (`scene_history_screen.dart`) and the Drive conflict preview
/// (`drive_conflict_screen.dart`) — both compare two versions of the same
/// text file and want the identical rendering.
class InlineTextDiff extends StatelessWidget {
  const InlineTextDiff({super.key, required this.from, required this.to});

  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    final diffs = DiffMatchPatch().diff(from, to);
    return SelectableText.rich(
      TextSpan(
        children: [
          for (final d in diffs)
            TextSpan(
              text: d.text,
              style: switch (d.operation) {
                DIFF_INSERT => TextStyle(
                    backgroundColor: Colors.green.withValues(alpha: 0.25),
                  ),
                DIFF_DELETE => TextStyle(
                    backgroundColor: Colors.red.withValues(alpha: 0.25),
                    decoration: TextDecoration.lineThrough,
                  ),
                _ => null,
              },
            ),
        ],
      ),
    );
  }
}
