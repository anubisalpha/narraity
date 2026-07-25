import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/profile_entry.dart';

const _uuid = Uuid();

/// Reads/writes a project's character profiles (`characters/char-<id>.json`)
/// or worldbuilding entries (`worldbuilding/entry-<id>.json`) — see PLAN.md
/// "Data model". One service handles both because the only differences are
/// the folder, the id prefix, and which starter fields a new entry gets;
/// everything else (CRUD, images, categories) is identical, and two copies
/// would just be two places to fix every bug.
class ProfileService {
  ProfileService(this.projectDir, this.kind);

  final Directory projectDir;
  final ProfileKind kind;

  String get _subdirectory =>
      kind == ProfileKind.character ? 'characters' : 'worldbuilding';

  String get _idPrefix => kind == ProfileKind.character ? 'char' : 'entry';

  Directory get _dir => Directory(p.join(projectDir.path, _subdirectory));

  Directory get _imagesDir => Directory(p.join(projectDir.path, 'assets', 'images'));

  /// All entries, sorted by name (case-insensitive) so the sidebar order is
  /// predictable rather than filesystem-dependent.
  Future<List<ProfileEntry>> list() async {
    if (!await _dir.exists()) return [];

    final entries = <ProfileEntry>[];
    await for (final entity in _dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        entries.add(ProfileEntry.fromJson(json));
      } catch (_) {
        continue; // skip a corrupt file rather than emptying the whole panel
      }
    }

    entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return entries;
  }

  Future<ProfileEntry> create({required String name, String? category}) async {
    final now = DateTime.now();
    final entry = ProfileEntry(
      id: '$_idPrefix-${_uuid.v4()}',
      name: name,
      category: category,
      fields: ProfileEntry.starterFields(kind),
      created: now,
      modified: now,
    );
    await save(entry);
    return entry;
  }

  Future<void> save(ProfileEntry entry) async {
    await _dir.create(recursive: true);
    await _fileFor(entry.id)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(entry.toJson()));
  }

  /// Deletes the entry and its attached image — an orphaned image would
  /// otherwise sit in `assets/` forever, and get carried into every vault
  /// backup.
  Future<void> delete(ProfileEntry entry) async {
    final file = _fileFor(entry.id);
    if (await file.exists()) await file.delete();
    await _deleteImageFile(entry);
  }

  /// Distinct categories currently in use, sorted — drives the grouped world
  /// sidebar and the category autocomplete, so the author's own vocabulary is
  /// offered back to them instead of a fixed list.
  Future<List<String>> categories() async {
    final entries = await list();
    final categories = entries
        .map((e) => e.category)
        .whereType<String>()
        .where((c) => c.trim().isNotEmpty)
        .toSet()
        .toList();
    categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return categories;
  }

  /// Copies [source] into `assets/images/` and returns the entry pointing at
  /// it. The image is copied rather than referenced in place because the
  /// original could be anywhere (a Downloads folder, a USB stick) and a
  /// project has to stay self-contained to be portable and backup-able.
  Future<ProfileEntry> attachImage(ProfileEntry entry, File source) async {
    await _imagesDir.create(recursive: true);

    // Remove any previous image first: the new one may have a different
    // extension, in which case overwriting wouldn't replace it.
    await _deleteImageFile(entry);

    final extension = p.extension(source.path).toLowerCase();
    final fileName = '${entry.id}$extension';
    await source.copy(p.join(_imagesDir.path, fileName));

    final updated = entry.copyWith(
      imagePath: p.join('assets', 'images', fileName).replaceAll('\\', '/'),
    );
    await save(updated);
    return updated;
  }

  Future<ProfileEntry> removeImage(ProfileEntry entry) async {
    await _deleteImageFile(entry);
    final updated = entry.copyWith(clearImage: true);
    await save(updated);
    return updated;
  }

  /// Absolute file for [entry]'s image, or null if it has none. The stored
  /// path is project-relative, so it needs resolving against [projectDir]
  /// before any widget can load it.
  File? imageFile(ProfileEntry entry) {
    final path = entry.imagePath;
    if (path == null) return null;
    return File(p.join(projectDir.path, path));
  }

  File _fileFor(String id) => File(p.join(_dir.path, '$id.json'));

  Future<void> _deleteImageFile(ProfileEntry entry) async {
    final image = imageFile(entry);
    if (image != null && await image.exists()) {
      await image.delete();
    }
  }
}
