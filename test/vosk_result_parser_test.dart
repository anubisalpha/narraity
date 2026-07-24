import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/vosk_result_parser.dart';

void main() {
  test('parseFinal extracts the "text" field', () {
    expect(VoskResultParser.parseFinal('{"text": "hello world"}'), 'hello world');
  });

  test('parsePartial extracts the "partial" field', () {
    expect(VoskResultParser.parsePartial('{"partial": "hel"}'), 'hel');
  });

  test('empty text field yields empty string, not null-crash', () {
    expect(VoskResultParser.parseFinal('{"text": ""}'), '');
  });

  test('malformed JSON returns empty string rather than throwing', () {
    expect(VoskResultParser.parseFinal('not json'), '');
    expect(VoskResultParser.parsePartial(''), '');
  });

  test('missing key returns empty string', () {
    expect(VoskResultParser.parseFinal('{"partial": "x"}'), '');
  });
}
