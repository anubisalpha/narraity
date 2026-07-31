import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/filename_sanitizer.dart';

void main() {
  group('sanitizeFileName', () {
    test('strips Windows-reserved characters', () {
      expect(sanitizeFileName('Book 1: Wisdom of the Elders'),
          'Book 1_ Wisdom of the Elders');
      expect(sanitizeFileName('a/b\\c:d*e?f"g<h>i|j'), 'a_b_c_d_e_f_g_h_i_j');
    });

    test('trims whitespace', () {
      expect(sanitizeFileName('  My Title  '), 'My Title');
    });

    test('falls back to Untitled for empty or all-illegal input', () {
      expect(sanitizeFileName(''), 'Untitled');
      expect(sanitizeFileName('   '), 'Untitled');
    });
  });
}
