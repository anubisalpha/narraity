import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/spell_check_provider.dart';

/// Lists every word spell check flagged on the currently open scene, docked
/// under the editor (same slot/pattern as `AnnotationPanel`). Each row shows
/// suggestion chips (tap to replace in place) and an "add to dictionary"
/// action for names/words that are correct but not in Hunspell's wordlist.
class SpellingPanel extends ConsumerWidget {
  const SpellingPanel({
    super.key,
    required this.content,
    required this.misspelled,
    required this.onJumpTo,
    required this.onReplace,
    required this.onAddToDictionary,
  });

  final String content;
  final List<(int start, int end)> misspelled;
  final void Function(int start, int end) onJumpTo;
  final void Function(int start, int end, String replacement) onReplace;
  final void Function(String word) onAddToDictionary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (misspelled.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No spelling issues found on this scene.'),
      );
    }

    final serviceAsync = ref.watch(spellCheckServiceProvider);
    final service = serviceAsync.valueOrNull;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final (start, end) in misspelled)
            _SpellingTile(
              word: content.substring(start, end),
              suggestions: service?.suggestionsFor(content.substring(start, end)) ?? const [],
              onJumpTo: () => onJumpTo(start, end),
              onReplace: (replacement) => onReplace(start, end, replacement),
              onAddToDictionary: () => onAddToDictionary(content.substring(start, end)),
            ),
        ],
      ),
    );
  }
}

class _SpellingTile extends StatelessWidget {
  const _SpellingTile({
    required this.word,
    required this.suggestions,
    required this.onJumpTo,
    required this.onReplace,
    required this.onAddToDictionary,
  });

  final String word;
  final List<String> suggestions;
  final VoidCallback onJumpTo;
  final ValueChanged<String> onReplace;
  final VoidCallback onAddToDictionary;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.spellcheck, color: Colors.red),
      title: Text(word),
      onTap: onJumpTo,
      subtitle: suggestions.isEmpty
          ? const Text('No suggestions')
          : Wrap(
              spacing: 6,
              children: [
                for (final suggestion in suggestions.take(5))
                  ActionChip(
                    label: Text(suggestion),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onReplace(suggestion),
                  ),
              ],
            ),
      trailing: IconButton(
        tooltip: 'Add to dictionary',
        icon: const Icon(Icons.add_circle_outline, size: 18),
        onPressed: onAddToDictionary,
      ),
    );
  }
}
