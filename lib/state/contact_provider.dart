import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/contact.dart';
import '../services/contact_service.dart';
import 'library_provider.dart';

final contactServiceProvider = Provider<ContactService>(
  (ref) => ContactService(ref.watch(libraryServiceProvider)),
);

/// All saved contacts, alphabetical by name. Invalidate after
/// creating/updating/deleting a contact.
final contactListProvider = FutureProvider<List<Contact>>((ref) async {
  final service = ref.watch(contactServiceProvider);
  return service.listContacts();
});
