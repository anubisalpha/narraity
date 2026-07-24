import 'dart:convert';

/// Parses Vosk's JSON result strings. `getResult`/`getFinalResult` return
/// `{"text": "..."}`; `getPartialResult` returns `{"partial": "..."}`. Pure
/// parsing logic — no FFI/platform dependency, fully unit-testable.
class VoskResultParser {
  VoskResultParser._();

  static String parseFinal(String json) => _extract(json, 'text');

  static String parsePartial(String json) => _extract(json, 'partial');

  static String _extract(String json, String key) {
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return (decoded[key] as String?)?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }
}
