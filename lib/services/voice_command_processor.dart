/// Converts spoken punctuation/formatting commands into their symbols, so
/// dictated speech isn't one unpunctuated stream (PLAN.md "Voice commands").
/// Pure text transform — no platform dependency, fully unit-testable.
class VoiceCommandProcessor {
  VoiceCommandProcessor._();

  /// Longest phrases first, so "new paragraph" matches before a hypothetical
  /// future "new" command would.
  static final List<(RegExp, String)> _commands = [
    (RegExp(r'\bnew paragraph\b', caseSensitive: false), '\n\n'),
    (RegExp(r'\bnew line\b', caseSensitive: false), '\n'),
    (RegExp(r'\bfull stop\b', caseSensitive: false), '.'),
    (RegExp(r'\bperiod\b', caseSensitive: false), '.'),
    (RegExp(r'\bcomma\b', caseSensitive: false), ','),
    (RegExp(r'\bquestion mark\b', caseSensitive: false), '?'),
    (RegExp(r'\bexclamation (mark|point)\b', caseSensitive: false), '!'),
  ];

  /// Applies command substitutions and tidies whitespace left behind (e.g.
  /// a space before a comma/period from "hello comma world" -> "hello, world").
  static String process(String rawText) {
    var text = rawText;
    for (final (pattern, replacement) in _commands) {
      text = text.replaceAll(pattern, replacement);
    }
    // Collapse " ," / " ." / " ?" / " !" left over from substitution.
    text = text.replaceAllMapped(
      RegExp(r' +([,.?!])'),
      (match) => match.group(1)!,
    );
    // Strip spaces left clinging to a newline from "word new paragraph word".
    text = text.replaceAll(RegExp(r' *\n *'), '\n');
    // Collapse runs of spaces (but not the newlines from paragraph/line breaks).
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    return text;
  }
}
