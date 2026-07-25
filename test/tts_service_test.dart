import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/tts_service.dart';

void main() {
  group('parseTtsVoices', () {
    test('extracts name and locale from each voice map', () {
      final voices = parseTtsVoices([
        {'name': 'Microsoft Zira', 'locale': 'en-US'},
        {'name': 'Microsoft Hazel', 'locale': 'en-GB'},
      ]);

      expect(voices, hasLength(2));
      expect(voices[0].name, 'Microsoft Zira');
      expect(voices[0].locale, 'en-US');
      expect(voices[1].name, 'Microsoft Hazel');
      expect(voices[1].locale, 'en-GB');
    });

    test('skips entries with no name', () {
      final voices = parseTtsVoices([
        {'locale': 'en-US'},
        {'name': 'Valid Voice', 'locale': 'en-GB'},
      ]);

      expect(voices, hasLength(1));
      expect(voices.single.name, 'Valid Voice');
    });

    test('defaults locale to empty when missing, rather than throwing', () {
      final voices = parseTtsVoices([
        {'name': 'No Locale Voice'},
      ]);

      expect(voices.single.locale, '');
    });

    test('non-list input returns an empty list rather than throwing', () {
      expect(parseTtsVoices(null), isEmpty);
      expect(parseTtsVoices('not a list'), isEmpty);
      expect(parseTtsVoices(42), isEmpty);
    });

    test('non-map entries in the list are skipped', () {
      final voices = parseTtsVoices([
        'not a map',
        {'name': 'Valid Voice', 'locale': 'en-GB'},
      ]);

      expect(voices, hasLength(1));
    });
  });

  group('TtsVoice equality', () {
    test('two voices with the same name and locale are equal', () {
      const a = TtsVoice(name: 'Hazel', locale: 'en-GB');
      const b = TtsVoice(name: 'Hazel', locale: 'en-GB');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('voices differing in locale are not equal', () {
      const a = TtsVoice(name: 'Hazel', locale: 'en-GB');
      const b = TtsVoice(name: 'Hazel', locale: 'en-US');
      expect(a, isNot(equals(b)));
    });
  });
}
