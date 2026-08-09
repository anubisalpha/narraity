import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/contact.dart';
import 'package:narraity/services/contact_service.dart';
import 'package:narraity/services/library_service.dart';

void main() {
  late Directory tempDir;
  late ContactService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_contact_test_');
    service = ContactService(LibraryService(rootOverride: tempDir));
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('a fresh library has no contacts', () async {
    expect(await service.listContacts(), isEmpty);
  });

  test('createContact persists to _Contacts/ and round-trips', () async {
    final contact = await service.createContact(
      name: 'Sarah',
      role: ContactRole.betaReader,
      email: 'sarah@example.com',
    );

    expect(
      File('${tempDir.path}/_Contacts/contact-${contact.id}.json').existsSync(),
      isTrue,
    );
    final contacts = await service.listContacts();
    expect(contacts.single.name, 'Sarah');
    expect(contacts.single.role, ContactRole.betaReader);
    expect(contacts.single.email, 'sarah@example.com');
  });

  test('updateContact persists edits and bumps modified', () async {
    final contact = await service.createContact(name: 'Dave', role: ContactRole.editor);
    final originalModified = contact.modified;
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await service.updateContact(contact.copyWith(name: 'Dave Smith'));

    final reloaded = (await service.listContacts()).single;
    expect(reloaded.name, 'Dave Smith');
    expect(reloaded.modified.isAfter(originalModified), isTrue);
  });

  test('deleteContact removes only the targeted contact', () async {
    final keep = await service.createContact(name: 'Keep', role: ContactRole.agent);
    final drop = await service.createContact(name: 'Drop', role: ContactRole.agent);

    await service.deleteContact(drop);

    final remaining = await service.listContacts();
    expect(remaining.single.id, keep.id);
  });

  test('listContacts sorts alphabetically by name', () async {
    await service.createContact(name: 'Zed', role: ContactRole.other);
    await service.createContact(name: 'Amy', role: ContactRole.other);

    final contacts = await service.listContacts();
    expect(contacts.map((c) => c.name), ['Amy', 'Zed']);
  });
}
