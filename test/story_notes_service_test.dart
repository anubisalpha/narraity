import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/story_notes_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory projectDir;
  late StoryNotesService notes;

  setUp(() {
    projectDir = Directory.systemTemp.createTempSync('narraity_notes_test_');
    notes = StoryNotesService(projectDir);
  });

  tearDown(() => projectDir.deleteSync(recursive: true));

  test('a project with no notes lists nothing', () async {
    expect(await notes.listAll(), isEmpty);
    expect(await notes.folders(), isEmpty);
  });

  test('notes round-trip with title, body and tags', () async {
    await notes.createNote(
      title: 'The ending',
      body: 'Elena walks away from the Concord.',
      tags: ['plot', 'ending'],
    );

    final loaded = (await notes.listAll()).single;
    expect(loaded.title, 'The ending');
    expect(loaded.body, 'Elena walks away from the Concord.');
    expect(loaded.tags, ['plot', 'ending']);
    expect(loaded.folder, isNull);
  });

  test('notes are listed newest-modified first', () async {
    final first = await notes.createNote(title: 'First');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await notes.createNote(title: 'Second');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await notes.save(first.copyWith(body: 'edited'));

    expect((await notes.listAll()).map((n) => n.title), ['First', 'Second']);
  });

  test('a note promoted from a Global Idea is readable', () async {
    // Exactly the shape IdeasService._seedNote writes: no `modified`, an id
    // that already carries the note- prefix, and a source marker.
    final dir = Directory(p.join(projectDir.path, 'notes'));
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'note-abc.json')).writeAsString(jsonEncode({
      'id': 'note-abc',
      'title': 'A captured idea',
      'body': 'What if the Concord was right all along?',
      'tags': ['premise'],
      'source': 'globalIdea',
      'created': DateTime.now().toIso8601String(),
    }));

    final loaded = (await notes.listAll()).single;
    expect(loaded.title, 'A captured idea');
    expect(loaded.source, 'globalIdea');
    expect(loaded.modified, loaded.created);
  });

  test('deleting removes the note', () async {
    final note = await notes.createNote(title: 'Temporary');
    await notes.delete(note);
    expect(await notes.listAll(), isEmpty);
  });

  test('a corrupt note file is skipped rather than breaking the panel', () async {
    await notes.createNote(title: 'Good note');
    await File(p.join(projectDir.path, 'notes', 'note-broken.json'))
        .writeAsString('{not json');

    expect((await notes.listAll()).map((n) => n.title), ['Good note']);
  });

  group('folders', () {
    test('a note saved into a folder reports that folder', () async {
      await notes.createFolder('Research');
      await notes.createNote(title: 'Filed', folder: 'Research');

      expect(await notes.folders(), ['Research']);
      final loaded = (await notes.listAll()).single;
      expect(loaded.folder, 'Research');
      expect(
        await File(p.join(projectDir.path, 'notes', 'Research', '${loaded.id}.json'))
            .exists(),
        isTrue,
      );
    });

    test('moving a note relocates the file and updates its folder', () async {
      await notes.createFolder('Research');
      final note = await notes.createNote(title: 'Movable');

      final moved = await notes.moveToFolder(note, 'Research');
      expect(moved.folder, 'Research');
      expect(await File(p.join(projectDir.path, 'notes', '${note.id}.json')).exists(),
          isFalse);

      final backToRoot = await notes.moveToFolder(moved, null);
      expect(backToRoot.folder, isNull);
      expect((await notes.listAll()).single.folder, isNull);
    });

    test('renaming a folder keeps its notes', () async {
      await notes.createFolder('Reserch');
      await notes.createNote(title: 'Filed', folder: 'Reserch');

      await notes.renameFolder('Reserch', 'Research');

      expect(await notes.folders(), ['Research']);
      expect((await notes.listAll()).single.folder, 'Research');
    });

    test('deleting a folder moves its notes to the root instead of destroying them',
        () async {
      await notes.createFolder('Research');
      await notes.createNote(title: 'Filed', folder: 'Research');

      await notes.deleteFolder('Research');

      expect(await notes.folders(), isEmpty);
      final loaded = (await notes.listAll()).single;
      expect(loaded.title, 'Filed');
      expect(loaded.folder, isNull);
    });

    test('folder names that would escape the notes folder are sanitised', () async {
      await notes.createFolder('../escape');

      expect(await notes.folders(), ['..escape']);
      expect(await Directory(p.join(projectDir.path, 'escape')).exists(), isFalse);
    });
  });

  group('search', () {
    setUp(() async {
      await notes.createNote(
        title: 'Elena Vance',
        body: 'The captain of the Ashfall garrison.',
        tags: ['character'],
      );
      await notes.createNote(
        title: 'Chapter three problems',
        body: 'Elena has nothing to do in this chapter.',
        tags: ['plot'],
      );
      await notes.createNote(
        title: 'Magic rules',
        body: 'Casting costs memory.',
        tags: ['worldbuilding', 'magic'],
      );
    });

    test('an empty query returns nothing', () async {
      expect(await notes.search(''), isEmpty);
      expect(await notes.search('   '), isEmpty);
    });

    test('matches title, body and tags, case-insensitively', () async {
      expect((await notes.search('MAGIC')).map((n) => n.title), contains('Magic rules'));
      expect((await notes.search('memory')).map((n) => n.title), ['Magic rules']);
      expect((await notes.search('worldbuilding')).map((n) => n.title), ['Magic rules']);
    });

    test('a title hit outranks a body hit', () async {
      final results = await notes.search('elena');

      expect(results.map((n) => n.title), ['Elena Vance', 'Chapter three problems']);
    });

    test('extra terms narrow the results', () async {
      expect((await notes.search('elena')).length, 2);
      expect((await notes.search('elena chapter')).map((n) => n.title),
          ['Chapter three problems']);
      expect(await notes.search('elena unicorns'), isEmpty);
    });

    test('a newly saved note is findable immediately', () async {
      await notes.createNote(title: 'Brand new', body: 'mentions unicorns');

      expect((await notes.search('unicorns')).map((n) => n.title), ['Brand new']);
    });

    test('an edited note is searchable by its new text, not its old', () async {
      final note = (await notes.search('memory')).single;
      await notes.save(note.copyWith(body: 'Casting costs blood.'));

      expect(await notes.search('memory'), isEmpty);
      expect((await notes.search('blood')).map((n) => n.title), ['Magic rules']);
    });

    test('a deleted note stops appearing in results', () async {
      final note = (await notes.search('memory')).single;
      await notes.delete(note);

      expect(await notes.search('memory'), isEmpty);
    });

    test('a note moved into a folder is still findable', () async {
      await notes.createFolder('Research');
      final note = (await notes.search('memory')).single;
      await notes.moveToFolder(note, 'Research');

      final found = (await notes.search('memory')).single;
      expect(found.folder, 'Research');
    });
  });
}
