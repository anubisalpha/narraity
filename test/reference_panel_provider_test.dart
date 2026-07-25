import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/profile_entry.dart';
import 'package:narraity/state/reference_panel_provider.dart';

ProfileEntry _entry(String id, String name) {
  final now = DateTime.now();
  return ProfileEntry(id: id, name: name, created: now, modified: now);
}

void main() {
  final elena = _entry('char-1', 'Elena Vance');
  final mikhail = _entry('char-2', 'Mikhail');
  final keep = _entry('entry-1', 'Ashfall Keep');
  final impostor = _entry('entry-2', 'Elena Vance'); // world entry, same name

  group('resolveMentions', () {
    test('matches names case-insensitively', () {
      final result = resolveMentions(['elena vance'], [elena, mikhail], [keep]);
      expect(result.entries.map((i) => i.entry), [elena]);
      expect(result.unresolved, isEmpty);
    });

    test('matches world entries too', () {
      final result = resolveMentions(['Ashfall Keep'], [elena], [keep]);
      expect(result.entries.map((i) => i.entry), [keep]);
    });

    test('a character wins a name collision with a world entry', () {
      final result = resolveMentions(['Elena Vance'], [elena], [impostor]);
      expect(result.entries.map((i) => i.entry), [elena]);
    });

    test('unknown names come back as unresolved, in order', () {
      final result =
          resolveMentions(['Elena Vance', 'Nobody', 'Also Nobody'], [elena], []);
      expect(result.entries.map((i) => i.entry), [elena]);
      expect(result.unresolved, ['Nobody', 'Also Nobody']);
    });

    test('order follows mention order, not entry-list order', () {
      final result =
          resolveMentions(['Mikhail', 'Elena Vance'], [elena, mikhail], []);
      expect(result.entries.map((i) => i.entry), [mikhail, elena]);
    });

    test('no mentions resolves to nothing', () {
      final result = resolveMentions([], [elena], [keep]);
      expect(result.entries, isEmpty);
      expect(result.unresolved, isEmpty);
    });

    test('each match carries which collection it came from', () {
      // The card needs this to pick the right service for an inline edit;
      // inferring it from the id prefix would send a hand-edited character's
      // changes into the worldbuilding folder.
      final result =
          resolveMentions(['Elena Vance', 'Ashfall Keep'], [elena], [keep]);

      expect(result.entries.map((i) => i.kind),
          [ProfileKind.character, ProfileKind.world]);
    });

    test('an entry whose id lacks the usual prefix still gets the right kind', () {
      final handEdited = _entry('imported-42', 'Hand Written');
      final result = resolveMentions(['Hand Written'], [handEdited], []);

      expect(result.entries.single.kind, ProfileKind.character);
    });
  });
}
