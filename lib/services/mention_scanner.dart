/// Parsing for `[[Name]]` reference mentions in scene text, and detection of
/// an in-progress `@` autocomplete query at the caret.
///
/// Mentions are name-based rather than id-based (user decision, 2026-07-25):
/// `[[Elena Vance]]` stays readable in a plain-text editor, at the cost that
/// renaming a character orphans old mentions until the author fixes them with
/// Find & Replace. Resolution against actual entries happens at scan time —
/// see resolveMentions in reference_panel_provider.dart — so an orphaned
/// mention degrades to an "unresolved" chip, never an error.
library;

final _mentionPattern = RegExp(r'\[\[([^\[\]\n]+)\]\]');

/// Names mentioned in [text], first-seen order, de-duplicated
/// case-insensitively (keeping the first casing encountered).
List<String> extractMentions(String text) {
  final seen = <String>{};
  final names = <String>[];
  for (final match in _mentionPattern.allMatches(text)) {
    final name = match.group(1)!.trim();
    if (name.isEmpty) continue;
    if (seen.add(name.toLowerCase())) names.add(name);
  }
  return names;
}

/// An in-progress mention query: the user has typed `@` plus [query], with
/// the `@` at [start]. Replacing [start]..caret with `[[Name]] ` completes it.
class MentionQuery {
  const MentionQuery(this.start, this.query);

  final int start;
  final String query;
}

/// Returns the active `@` query ending at [caret], or null when the caret
/// isn't inside one.
///
/// The `@` must sit at the start of the text or after whitespace/opening
/// punctuation — `name@example.com` must not trigger autocomplete. The query
/// is capped at 40 characters and can't span lines or brackets, so an `@`
/// used in ordinary prose stops offering completions as soon as it stops
/// looking like a name.
MentionQuery? mentionQueryAt(String text, int caret) {
  if (caret < 0 || caret > text.length) return null;

  final before = text.substring(0, caret);
  final at = before.lastIndexOf('@');
  if (at < 0) return null;

  final query = before.substring(at + 1);
  if (query.length > 40) return null;
  if (query.contains('\n') || query.contains('[') || query.contains(']')) return null;

  if (at > 0 && !RegExp(r'''[\s("'—‘“-]''').hasMatch(before[at - 1])) {
    return null;
  }
  return MentionQuery(at, query);
}
