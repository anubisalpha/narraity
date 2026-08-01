import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/library_background.dart';

void main() {
  group('contrastRatio', () {
    test('pure black vs pure white is the maximum, 21:1', () {
      expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
    });

    test('identical colors have the minimum ratio, 1:1', () {
      expect(contrastRatio(Colors.red, Colors.red), closeTo(1, 0.01));
    });

    test('is symmetric regardless of argument order', () {
      final a = contrastRatio(Colors.blue, Colors.yellow);
      final b = contrastRatio(Colors.yellow, Colors.blue);
      expect(a, closeTo(b, 0.0001));
    });
  });

  group('hasAdequateContrast', () {
    test('the theme-default choice always passes (no custom color to check)', () {
      expect(hasAdequateContrast(const ThemeDefaultBackground()), isTrue);
    });

    test('a solid color picks its own flat color as representative', () {
      const choice = SolidBackground(Color(0xFF000000), 'test-black', 'Test Black');
      expect(choice.representativeColor, const Color(0xFF000000));
    });

    test('a gradient picks the lighter of its two stops as representative', () {
      const choice = GradientBackground(
        [Color(0xFF000000), Color(0xFFFFFFFF)],
        'test-gradient',
        'Test Gradient',
      );
      expect(choice.representativeColor, const Color(0xFFFFFFFF));
    });

    test('a genuinely low-contrast mid-gray fails the check', () {
      // Mid-gray is the classic worst case: too close to both black and
      // white to clear 4.5:1 against either.
      const choice = SolidBackground(Color(0xFF808080), 'test-midgray', 'Test Mid-Gray');
      expect(hasAdequateContrast(choice), isFalse);
    });

    test('a near-white color passes (pairs with black text)', () {
      const choice = SolidBackground(Color(0xFFF5F5F5), 'test-nearwhite', 'Test Near White');
      expect(hasAdequateContrast(choice), isTrue);
    });

    test('a near-black color passes (pairs with white text)', () {
      const choice = SolidBackground(Color(0xFF0A0A0A), 'test-nearblack', 'Test Near Black');
      expect(hasAdequateContrast(choice), isTrue);
    });
  });

  group('curated presets', () {
    test('every curated preset passes its own contrast check — the whole point of curating '
        'them', () {
      for (final choice in kLibraryBackgroundChoices) {
        expect(
          hasAdequateContrast(choice),
          isTrue,
          reason: '"${choice.label}" (${choice.id}) should have adequate contrast — if this '
              'fails, either fix the preset\'s color or reconsider curating it at all',
        );
      }
    });

    test('the first preset is always the theme-default option', () {
      expect(kLibraryBackgroundChoices.first, isA<ThemeDefaultBackground>());
    });

    test('every preset has a unique id', () {
      final ids = kLibraryBackgroundChoices.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('libraryBackgroundChoiceById', () {
    test('resolves a known id to its preset', () {
      final choice = libraryBackgroundChoiceById('solid-parchment');
      expect(choice.label, 'Parchment');
    });

    test('falls back to the theme-default choice for an unknown id (e.g. a stale saved '
        'preference from a removed preset)', () {
      final choice = libraryBackgroundChoiceById('no-such-id');
      expect(choice, isA<ThemeDefaultBackground>());
    });
  });
}
