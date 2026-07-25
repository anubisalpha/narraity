import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/relationship.dart';
import 'package:narraity/services/relationship_service.dart';

void main() {
  late Directory tempDir;
  late RelationshipService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_relationship_test_');
    service = RelationshipService(tempDir);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('empty project has no relationships or layout', () async {
    expect(await service.listRelationships(), isEmpty);
    expect(await service.loadLayout(), isEmpty);
  });

  test('addRelationship persists and round-trips', () async {
    await service.addRelationship(
      characterAId: 'char-1',
      characterBId: 'char-2',
      type: RelationshipType.family,
      label: 'siblings',
    );

    final relationships = await service.listRelationships();
    expect(relationships.single.characterAId, 'char-1');
    expect(relationships.single.characterBId, 'char-2');
    expect(relationships.single.type, RelationshipType.family);
    expect(relationships.single.label, 'siblings');
  });

  test('saveRelationship updates type and label in place', () async {
    final relationship = await service.addRelationship(
      characterAId: 'char-1',
      characterBId: 'char-2',
      type: RelationshipType.friend,
    );
    await service.saveRelationship(
      relationship.copyWith(type: RelationshipType.rival, label: 'former friends'),
    );

    final reloaded = (await service.listRelationships()).single;
    expect(reloaded.type, RelationshipType.rival);
    expect(reloaded.label, 'former friends');
  });

  test('deleteRelationship removes only the targeted edge', () async {
    final keep = await service.addRelationship(
        characterAId: 'char-1', characterBId: 'char-2', type: RelationshipType.ally);
    final drop = await service.addRelationship(
        characterAId: 'char-1', characterBId: 'char-3', type: RelationshipType.rival);

    await service.deleteRelationship(drop.id);

    final remaining = await service.listRelationships();
    expect(remaining.single.id, keep.id);
  });

  test('relationshipsFor returns edges touching a character from either side', () async {
    await service.addRelationship(
        characterAId: 'char-1', characterBId: 'char-2', type: RelationshipType.ally);
    await service.addRelationship(
        characterAId: 'char-3', characterBId: 'char-1', type: RelationshipType.rival);
    await service.addRelationship(
        characterAId: 'char-2', characterBId: 'char-3', type: RelationshipType.friend);

    final forChar1 = await service.relationshipsFor('char-1');
    expect(forChar1, hasLength(2));
  });

  test('setNodePosition persists and round-trips', () async {
    await service.setNodePosition('char-1', 12.5, 34.5);

    final layout = await service.loadLayout();
    expect(layout['char-1'], (12.5, 34.5));
  });

  test('setNodePosition on an existing character overwrites, others untouched', () async {
    await service.setNodePosition('char-1', 0, 0);
    await service.setNodePosition('char-2', 10, 10);
    await service.setNodePosition('char-1', 99, 99);

    final layout = await service.loadLayout();
    expect(layout['char-1'], (99.0, 99.0));
    expect(layout['char-2'], (10.0, 10.0));
  });

  test('removeNodePosition drops only the targeted character', () async {
    await service.setNodePosition('char-1', 0, 0);
    await service.setNodePosition('char-2', 10, 10);

    await service.removeNodePosition('char-1');

    final layout = await service.loadLayout();
    expect(layout.containsKey('char-1'), isFalse);
    expect(layout['char-2'], (10.0, 10.0));
  });
}
