/// A project that's been archived or soft-deleted — its whole folder tree
/// was compressed into a single `.zip` under the library's reserved
/// `_Archived/`/`_Deleted/` folder (see `LibraryService`), rather than kept
/// as a live, listed project. `fileName` is the zip's name on disk, needed
/// to restore or (for a user who really wants it gone) manually delete it
/// from the filesystem themselves — this app never permanently deletes a
/// project on its own.
class ArchivedProject {
  const ArchivedProject({
    required this.fileName,
    required this.title,
    this.author,
    required this.archivedAt,
  });

  final String fileName;
  final String title;
  final String? author;
  final DateTime archivedAt;
}
