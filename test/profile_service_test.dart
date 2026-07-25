import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/profile_entry.dart';
import 'package:narraity/services/profile_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory projectDir;
  late ProfileService characters;
  late ProfileService world;

  setUp(() {
    projectDir = Directory.systemTemp.createTempSync('narraity_profile_test_');
    characters = ProfileService(projectDir, ProfileKind.character);
    world = ProfileService(projectDir, ProfileKind.world);
  });

  tearDown(() => projectDir.deleteSync(recursive: true));

  test('a project with no profiles lists nothing', () async {
    expect(await characters.list(), isEmpty);
    expect(await world.list(), isEmpty);
  });

  test('a new character is seeded with the starter field template', () async {
    final created = await characters.create(name: 'Elena Vance');

    expect(created.name, 'Elena Vance');
    expect(created.fields.keys, containsAll(['Role', 'Appearance', 'Backstory']));
    expect(created.fields.values, everyElement(isEmpty));
    expect(created.id, startsWith('char-'));
  });

  test('a new world entry seeds fewer fields than a character', () async {
    final entry = await world.create(name: 'Ashfall Keep', category: 'Location');

    expect(entry.fields.keys, ['Description']);
    expect(entry.category, 'Location');
    expect(entry.id, startsWith('entry-'));
  });

  test('characters and world entries are stored separately', () async {
    await characters.create(name: 'Elena');
    await world.create(name: 'Ashfall');

    expect((await characters.list()).map((e) => e.name), ['Elena']);
    expect((await world.list()).map((e) => e.name), ['Ashfall']);
  });

  test('edits round-trip, including field order and quickRef', () async {
    final created = await characters.create(name: 'Elena');
    await characters.save(created.copyWith(
      name: 'Elena Vance',
      fields: {'Role': 'Captain', 'Age': '34', 'Custom field': 'anything'},
      quickRef: ['Role', 'Age'],
    ));

    final loaded = (await characters.list()).single;
    expect(loaded.name, 'Elena Vance');
    expect(loaded.fields.keys.toList(), ['Role', 'Age', 'Custom field'],
        reason: 'author-chosen field order must survive a save/load cycle');
    expect(loaded.fields['Role'], 'Captain');
    expect(loaded.quickRef, ['Role', 'Age']);
  });

  test('entries are listed alphabetically regardless of creation order', () async {
    await characters.create(name: 'Zara');
    await characters.create(name: 'alice');
    await characters.create(name: 'Mikhail');

    expect((await characters.list()).map((e) => e.name), ['alice', 'Mikhail', 'Zara']);
  });

  test('a corrupt file is skipped rather than breaking the list', () async {
    await characters.create(name: 'Elena');
    await File(p.join(projectDir.path, 'characters', 'char-broken.json'))
        .writeAsString('{not valid json');

    expect((await characters.list()).map((e) => e.name), ['Elena']);
  });

  test('categories() returns distinct sorted values, ignoring blanks', () async {
    await world.create(name: 'Ashfall', category: 'Location');
    await world.create(name: 'Riverwatch', category: 'Location');
    await world.create(name: 'The Concord', category: 'Faction');
    await world.create(name: 'Uncategorised thing');

    expect(await world.categories(), ['Faction', 'Location']);
  });

  group('images', () {
    Future<File> sourceImage(String name, String bytes) async {
      final file = File(p.join(projectDir.path, name));
      await file.writeAsString(bytes);
      return file;
    }

    test('attaching copies the file into the project and stores a relative path',
        () async {
      final entry = await characters.create(name: 'Elena');
      final updated =
          await characters.attachImage(entry, await sourceImage('portrait.png', 'PNG'));

      expect(updated.imagePath, 'assets/images/${entry.id}.png');
      final stored = characters.imageFile(updated)!;
      expect(await stored.exists(), isTrue);
      expect(await stored.readAsString(), 'PNG');
      // Relative, so a moved or restored project folder still resolves.
      expect(p.isAbsolute(updated.imagePath!), isFalse);
    });

    test('replacing an image with a different extension leaves no orphan', () async {
      final entry = await characters.create(name: 'Elena');
      final withPng =
          await characters.attachImage(entry, await sourceImage('a.png', 'PNG'));
      final withJpg =
          await characters.attachImage(withPng, await sourceImage('b.jpg', 'JPG'));

      expect(withJpg.imagePath, endsWith('.jpg'));
      expect(await File(p.join(projectDir.path, withPng.imagePath!)).exists(), isFalse,
          reason: 'the old image must be deleted, not just unreferenced');
      expect(await characters.imageFile(withJpg)!.readAsString(), 'JPG');
    });

    test('removing an image clears the path and deletes the file', () async {
      final entry = await characters.create(name: 'Elena');
      final withImage =
          await characters.attachImage(entry, await sourceImage('a.png', 'PNG'));
      final imageFile = characters.imageFile(withImage)!;

      final cleared = await characters.removeImage(withImage);

      expect(cleared.imagePath, isNull);
      expect(await imageFile.exists(), isFalse);
      expect((await characters.list()).single.imagePath, isNull);
    });

    test('deleting an entry also deletes its image', () async {
      final entry = await characters.create(name: 'Elena');
      final withImage =
          await characters.attachImage(entry, await sourceImage('a.png', 'PNG'));
      final imageFile = characters.imageFile(withImage)!;

      await characters.delete(withImage);

      expect(await characters.list(), isEmpty);
      expect(await imageFile.exists(), isFalse,
          reason: 'an orphaned image would be carried into every vault backup');
    });
  });

  test('modified is refreshed on save but created is preserved', () async {
    final created = await characters.create(name: 'Elena');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await characters.save(created.copyWith(name: 'Elena Vance'));

    final loaded = (await characters.list()).single;
    expect(loaded.created, created.created);
    expect(loaded.modified.isAfter(created.modified), isTrue);
  });

  test('a hand-written minimal file still loads', () async {
    // Local-first storage invites hand editing; a file missing the optional
    // fields must not break the app.
    final dir = Directory(p.join(projectDir.path, 'characters'));
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'char-manual.json')).writeAsString(jsonEncode({
      'id': 'char-manual',
      'name': 'Hand Written',
      'created': DateTime.now().toIso8601String(),
    }));

    final loaded = (await characters.list()).single;
    expect(loaded.name, 'Hand Written');
    expect(loaded.fields, isEmpty);
    expect(loaded.quickRef, isEmpty);
    expect(loaded.modified, loaded.created);
  });
}
