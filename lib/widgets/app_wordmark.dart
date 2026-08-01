import 'package:flutter/material.dart';

/// The app's header brand mark: icon beside a styled "Narraity" wordmark,
/// matching the rest of the "-aity" app family's convention (Mosaity,
/// Explaity, aity.uk) — the "a" that starts the shared "-aity" suffix is
/// picked out in the theme's accent color with an underline, rest of the
/// word in the normal title color.
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.iconSize = 28, this.fontSize = 22});

  final double iconSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );
    final accentStyle = baseStyle.copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary,
      decorationThickness: 2,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/branding/app_icon.png', width: iconSize, height: iconSize),
        const SizedBox(width: 10),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'Narr', style: baseStyle),
              TextSpan(text: 'a', style: accentStyle),
              TextSpan(text: 'ity', style: baseStyle),
            ],
          ),
        ),
      ],
    );
  }
}
