import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/library_background.dart';
import '../state/library_background_provider.dart';

/// Swatch grid for picking a curated Library screen background — see
/// `library_background.dart`'s doc comment for why this is a fixed
/// preset list rather than a free color/gradient picker. Each swatch is a
/// tappable circle; the selected one gets a checkmark and a border ring.
/// Shows a contrast warning below the grid if the *currently selected*
/// choice's own vetting somehow failed (belt-and-braces — every curated
/// preset is expected to already pass, see the class doc, but the check
/// stays live rather than being a one-time assertion at build time only).
class LibraryBackgroundPicker extends ConsumerWidget {
  const LibraryBackgroundPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(libraryBackgroundProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final choice in kLibraryBackgroundChoices)
              _Swatch(
                choice: choice,
                isSelected: choice.id == selected.id,
                onTap: () =>
                    ref.read(libraryBackgroundProvider.notifier).select(choice),
              ),
          ],
        ),
        if (!hasAdequateContrast(selected)) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This background may be low-contrast against some text. Consider a different '
                  'option if anything looks hard to read.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.choice,
    required this.isSelected,
    required this.onTap,
  });

  final LibraryBackgroundChoice choice;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isThemeDefault = choice is ThemeDefaultBackground;

    return Tooltip(
      message: choice.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? scheme.primary : scheme.outlineVariant,
              width: isSelected ? 3 : 1,
            ),
          ),
          padding: const EdgeInsets.all(3),
          child: Container(
            decoration: isThemeDefault
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.outline),
                  )
                : (choice.decorationFor(context) as BoxDecoration).copyWith(
                    shape: BoxShape.circle,
                  ),
            child: isThemeDefault
                ? Icon(
                    Icons.format_paint_outlined,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  )
                : (isSelected
                      ? Icon(
                          Icons.check,
                          size: 18,
                          color:
                              choice.representativeColor.computeLuminance() >
                                  0.5
                              ? Colors.black
                              : Colors.white,
                        )
                      : null),
          ),
        ),
      ),
    );
  }
}
