import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/constant_time.dart';

void main() {
  group('constantTimeEquals', () {
    test('equal strings compare equal', () {
      expect(constantTimeEquals('abc123', 'abc123'), isTrue);
      expect(constantTimeEquals('', ''), isTrue);
    });

    test('strings differing anywhere compare unequal', () {
      expect(constantTimeEquals('abc123', 'abc124'), isFalse); // last char
      expect(constantTimeEquals('abc123', 'Xbc123'), isFalse); // first char
      expect(constantTimeEquals('abc123', 'abd123'), isFalse); // middle
    });

    test('different lengths compare unequal', () {
      expect(constantTimeEquals('abc', 'abcd'), isFalse);
      expect(constantTimeEquals('abcd', 'abc'), isFalse);
      expect(constantTimeEquals('', 'a'), isFalse);
    });

    test('a shared prefix is still unequal (no early-out on match run)', () {
      // The whole point: a long correct prefix must not read as equal.
      final a = 'f' * 63 + 'a';
      final b = 'f' * 63 + 'b';
      expect(constantTimeEquals(a, b), isFalse);
    });
  });

  group('constantTimeBytesEqual', () {
    test('equal byte lists compare equal', () {
      expect(constantTimeBytesEqual([1, 2, 3], [1, 2, 3]), isTrue);
      expect(constantTimeBytesEqual(const [], const []), isTrue);
    });

    test('unequal bytes or lengths compare unequal', () {
      expect(constantTimeBytesEqual([1, 2, 3], [1, 2, 4]), isFalse);
      expect(constantTimeBytesEqual([1, 2, 3], [1, 2]), isFalse);
      expect(constantTimeBytesEqual([1, 2], [1, 2, 3]), isFalse);
    });
  });
}
