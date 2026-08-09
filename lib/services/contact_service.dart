import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/contact.dart';
import 'library_service.dart';

const _uuid = Uuid();

/// Reads/writes `_Contacts/` at the library root — one `contact-<id>.json`
/// per contact, alongside (not inside) project folders, same "not tied to
/// one project" convention as `ReviewSessionService`'s `_ReviewSessions/`.
class ContactService {
  ContactService(this._library);

  final LibraryService _library;

  Future<Directory> _contactsDir() async {
    final root = await _library.libraryRoot();
    final dir = Directory(p.join(root.path, '_Contacts'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<Contact>> listContacts() async {
    final dir = await _contactsDir();
    final contacts = <Contact>[];

    await for (final entity in dir.list()) {
      if (entity is! File || !p.basename(entity.path).endsWith('.json')) {
        continue;
      }
      try {
        final json =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        contacts.add(Contact.fromJson(json));
      } catch (_) {
        continue; // skip corrupt files rather than breaking the list view
      }
    }

    contacts.sort((a, b) => a.name.compareTo(b.name));
    return contacts;
  }

  Future<Contact> createContact({
    required String name,
    required ContactRole role,
    String email = '',
    String notes = '',
  }) async {
    final contact = Contact(
      id: _uuid.v4(),
      name: name,
      role: role,
      email: email,
      notes: notes,
      created: DateTime.now(),
    );
    await _save(contact);
    return contact;
  }

  Future<void> updateContact(Contact contact) async {
    contact.modified = DateTime.now();
    await _save(contact);
  }

  Future<void> deleteContact(Contact contact) async {
    final dir = await _contactsDir();
    final file = File(p.join(dir.path, 'contact-${contact.id}.json'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _save(Contact contact) async {
    final dir = await _contactsDir();
    final file = File(p.join(dir.path, 'contact-${contact.id}.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(contact.toJson()),
    );
  }
}
