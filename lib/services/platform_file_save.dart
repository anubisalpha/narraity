import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Saves [bytes] to a location the user picks, papering over `file_picker`'s
/// platform split:
///
/// - **Android/iOS**: `saveFile` writes the file itself via the Storage Access
///   Framework and *requires* the bytes up front — passing only a path throws
///   `The "bytes" parameter is required on Android & iOS when calling
///   "saveFile"` (see narraity issue #9). It does not hand back a writable
///   filesystem path.
/// - **Desktop (Windows/macOS/Linux)**: `saveFile` returns a writable path and
///   we write the bytes to it ourselves; `bytes` isn't supported there.
///
/// Returns the saved location (a real path on desktop; whatever the mobile
/// picker reports, possibly null even on success) or null if the user
/// cancelled. Callers should treat a non-throwing return as success.
Future<String?> saveBytesToUserFile({
  required String dialogTitle,
  required String fileName,
  required List<int> bytes,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    return FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: type,
      allowedExtensions: allowedExtensions,
      bytes: Uint8List.fromList(bytes),
    );
  }

  final path = await FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: type,
    allowedExtensions: allowedExtensions,
    lockParentWindow: true,
  );
  if (path == null) return null;
  await File(path).writeAsBytes(bytes);
  return path;
}
