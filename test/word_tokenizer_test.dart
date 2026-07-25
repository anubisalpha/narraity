import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/word_tokenizer.dart';

void main() {
  test('splits plain prose into words with correct offsets', () {
    const content = 'Elena stepped through.';
    final words = tokenizeWords(content);

    expect(words.map((w) => w.text), ['Elena', 'stepped', 'through']);
    for (final word in words) {
      expect(content.substring(word.start, word.end), word.text);
    }
  });

  test('keeps a contraction as one word', () {
    final words = tokenizeWords("She didn't stop.");
    expect(words.map((w) => w.text), ["She", "didn't", 'stop']);
  });

  test('keeps a possessive/name with an apostrophe as one word', () {
    final words = tokenizeWords("O'Brien arrived.");
    expect(words.map((w) => w.text), ["O'Brien", 'arrived']);
  });

  test('does not match numbers or punctuation as words', () {
    final words = tokenizeWords('It cost 42 dollars, or so.');
    expect(words.map((w) => w.text), ['It', 'cost', 'dollars', 'or', 'so']);
  });

  test('single-letter words are still tokenized (e.g. "I" and "a")', () {
    final words = tokenizeWords('I saw a cat.');
    expect(words.map((w) => w.text), ['I', 'saw', 'a', 'cat']);
  });

  test('a [[mention]] is tokenized as plain words, brackets excluded', () {
    final words = tokenizeWords('She saw [[Elena Vance]] at the gate.');
    expect(words.map((w) => w.text), ['She', 'saw', 'Elena', 'Vance', 'at', 'the', 'gate']);
  });

  test('empty content has no words', () {
    expect(tokenizeWords(''), isEmpty);
  });
}
