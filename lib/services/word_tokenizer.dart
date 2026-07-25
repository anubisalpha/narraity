/// Splits scene content into words for spell-checking. Pure, no Flutter
/// dependency — same "keep parsing unit-testable" precedent as
/// `paragraph_splitter.dart` and `mention_scanner.dart`.
library;

class Word {
  const Word({required this.start, required this.end, required this.text});

  /// `[start, end)` character range in the original content string.
  final int start;
  final int end;
  final String text;
}

/// Letters, with an apostrophe allowed mid-word (`don't`, `O'Brien`) so
/// contractions and possessives aren't split into two spurious words.
/// Numbers, punctuation, and `[[mention]]` bracket syntax are never matched
/// — a mentioned name is still just a word to the tokenizer, spell-checked
/// like any other (the "add to dictionary" action is how a proper noun stops
/// being flagged, same as any real word processor).
final _wordPattern = RegExp(r"[A-Za-z]+(?:['’][A-Za-z]+)*");

List<Word> tokenizeWords(String content) => [
      for (final match in _wordPattern.allMatches(content))
        Word(start: match.start, end: match.end, text: match.group(0)!),
    ];
