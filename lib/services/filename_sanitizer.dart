/// Replaces characters that Windows (and file_picker's own validator) rejects
/// in a file name, so user-entered titles containing e.g. `:` never crash
/// FilePicker.saveFile's Windows isolate — see narraity issue #1.
String sanitizeFileName(String name) {
  final replaced = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  return replaced.isEmpty ? 'Untitled' : replaced;
}
