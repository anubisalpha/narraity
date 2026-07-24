import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/voice_command_processor.dart';

void main() {
  test('converts spoken punctuation to symbols', () {
    expect(
      VoiceCommandProcessor.process('hello comma world full stop'),
      'hello, world.',
    );
  });

  test('period is a synonym for full stop', () {
    expect(VoiceCommandProcessor.process('that is all period'), 'that is all.');
  });

  test('question mark and exclamation point', () {
    expect(VoiceCommandProcessor.process('really question mark'), 'really?');
    expect(
      VoiceCommandProcessor.process('wow exclamation point'),
      'wow!',
    );
    expect(
      VoiceCommandProcessor.process('wow exclamation mark'),
      'wow!',
    );
  });

  test('new paragraph and new line insert breaks', () {
    expect(
      VoiceCommandProcessor.process('first part new paragraph second part'),
      'first part\n\nsecond part',
    );
    expect(
      VoiceCommandProcessor.process('line one new line line two'),
      'line one\nline two',
    );
  });

  test('is case-insensitive', () {
    expect(VoiceCommandProcessor.process('hello COMMA world'), 'hello, world');
  });

  test('leaves ordinary text with no command phrases untouched', () {
    expect(
      VoiceCommandProcessor.process('the quick brown fox'),
      'the quick brown fox',
    );
  });

  test('collapses double spaces left over from substitution', () {
    expect(
      VoiceCommandProcessor.process('elena said comma  quietly'),
      'elena said, quietly',
    );
  });
}
