import 'package:flutter/material.dart';

/// One selectable Library screen background — either "follow the theme"
/// (the default, i.e. no custom background at all), a curated solid color,
/// or a curated two-color gradient. Deliberately a *fixed, curated* list
/// rather than a free-form color/gradient picker (decision 2026-08-01,
/// alongside the theme selector): a truly arbitrary color risks poor
/// contrast against the library grid's text (empty-state copy, FAB labels),
/// and every preset here is chosen to already read reasonably in both light
/// and dark mode. See [contrastRatio] for the (still-applied, belt-and-
/// braces) warning check even against these vetted choices.
sealed class LibraryBackgroundChoice {
  const LibraryBackgroundChoice(this.id, this.label);

  /// Persisted verbatim (see `library_background_provider.dart`) — stable
  /// identifier, not derived from list position, so reordering
  /// [kLibraryBackgroundChoices] later can't silently reassign someone's
  /// saved choice to a different preset.
  final String id;
  final String label;

  /// The single most representative color for a contrast check — the flat
  /// color itself for [SolidBackground], or the *lighter* of the two stops
  /// for [GradientBackground] (the more contrast-risky end, since text
  /// could sit anywhere along the gradient).
  Color get representativeColor;

  Decoration? decorationFor(BuildContext context) => null;
}

class ThemeDefaultBackground extends LibraryBackgroundChoice {
  const ThemeDefaultBackground() : super('theme', 'Match Theme');

  @override
  Color get representativeColor => Colors.transparent;

  @override
  Decoration? decorationFor(BuildContext context) => null;
}

class SolidBackground extends LibraryBackgroundChoice {
  const SolidBackground(this.color, String id, String label) : super(id, label);
  final Color color;

  @override
  Color get representativeColor => color;

  @override
  Decoration decorationFor(BuildContext context) => BoxDecoration(color: color);
}

class GradientBackground extends LibraryBackgroundChoice {
  const GradientBackground(this.colors, String id, String label)
    : super(id, label);
  final List<Color> colors;

  @override
  Color get representativeColor {
    // The stop with higher perceived luminance — text is more likely to
    // struggle against a lighter patch of the gradient than a darker one,
    // for the light-text-on-dark-theme case, and vice versa; checking the
    // lighter stop covers the more common "dark text" risk directly, and a
    // human still sees the whole gradient before picking one regardless.
    return colors.reduce(
      (a, b) => a.computeLuminance() >= b.computeLuminance() ? a : b,
    );
  }

  @override
  Decoration decorationFor(BuildContext context) => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
    ),
  );
}

/// The curated presets, in display order. `kLibraryBackgroundChoices.first`
/// is always [ThemeDefaultBackground] — the default for anyone who's never
/// changed this setting.
const kLibraryBackgroundChoices = <LibraryBackgroundChoice>[
  ThemeDefaultBackground(),
  SolidBackground(Color(0xFFE8E2D6), 'solid-parchment', 'Parchment'),
  SolidBackground(Color(0xFFD9E4E8), 'solid-mist', 'Mist'),
  SolidBackground(Color(0xFFE6DCE8), 'solid-lavender', 'Lavender'),
  SolidBackground(Color(0xFF2B2E33), 'solid-slate', 'Slate'),
  SolidBackground(Color(0xFF23303A), 'solid-midnight', 'Midnight'),
  GradientBackground(
    [Color(0xFFE8E2D6), Color(0xFFD9C7A3)],
    'gradient-dawn',
    'Dawn',
  ),
  GradientBackground(
    [Color(0xFFD9E4E8), Color(0xFFB8CDD6)],
    'gradient-harbor',
    'Harbor',
  ),
  GradientBackground(
    [Color(0xFF2B2E33), Color(0xFF3D2E3E)],
    'gradient-dusk',
    'Dusk',
  ),
  GradientBackground(
    [Color(0xFF23303A), Color(0xFF1B2A2E)],
    'gradient-deep-sea',
    'Deep Sea',
  ),
];

LibraryBackgroundChoice libraryBackgroundChoiceById(String id) {
  return kLibraryBackgroundChoices.firstWhere(
    (c) => c.id == id,
    orElse: () => const ThemeDefaultBackground(),
  );
}

/// WCAG relative-luminance-based contrast ratio between two colors — same
/// formula the accessibility guidelines KDP_CRIBSHEET.md already cites
/// (4.5:1 as the "AA" text-contrast minimum) use. Returns a value from 1
/// (identical, worst case) to 21 (pure black vs. pure white, best case).
double contrastRatio(Color a, Color b) {
  final lumA = a.computeLuminance() + 0.05;
  final lumB = b.computeLuminance() + 0.05;
  return lumA > lumB ? lumA / lumB : lumB / lumA;
}

/// Whether [background] has adequate contrast against the text color it
/// would realistically be paired with. A background's own luminance
/// determines which text color actually sits well on it — a light
/// background pairs with dark text and vice versa — so this checks against
/// *whichever* of black/white is the darker-vs-lighter match for
/// [LibraryBackgroundChoice.representativeColor]'s luminance, not both (an
/// "either one passes" check would be nearly meaningless: almost any color
/// has decent contrast against at least one of pure black or pure white).
bool hasAdequateContrast(LibraryBackgroundChoice background) {
  if (background is ThemeDefaultBackground) return true;
  const wcagAaMinimum = 4.5;
  final color = background.representativeColor;
  final pairedTextColor = color.computeLuminance() > 0.5
      ? Colors.black
      : Colors.white;
  return contrastRatio(color, pairedTextColor) >= wcagAaMinimum;
}
