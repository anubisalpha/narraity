import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/contact.dart';
import '../state/contact_provider.dart';
import '../widgets/help_drawer.dart';

/// Library-root contacts — agents, editors, beta readers, ARC reviewers, and
/// other people involved in getting a manuscript published. Not tied to any
/// one project, same "reachable from the Library screen" pattern as
/// `ReviewSessionsScreen`/`IdeasScreen`.
class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(contactListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: const [HelpIconButton(topicId: 'contacts'), SizedBox(width: 8)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showEditContactDialog(context, ref),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('New Contact'),
      ),
      body: contactsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Failed to load contacts: $err')),
        data: (contacts) => contacts.isEmpty
            ? const _EmptyContacts()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                itemCount: contacts.length,
                itemBuilder: (context, index) =>
                    _ContactCard(contact: contacts[index]),
              ),
      ),
    );
  }
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.contacts_outlined,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text('No contacts yet', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Add agents, editors, or beta readers to track them here.'),
        ],
      ),
    );
  }
}

class _ContactCard extends ConsumerWidget {
  const _ContactCard({required this.contact});

  final Contact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text(contact.name),
        subtitle: Text(
          '${contact.role.label}'
          '${contact.email.isEmpty ? '' : ' · ${contact.email}'}'
          ' · Added ${DateFormat.yMMMd().format(contact.created)}',
        ),
        onTap: () => showEditContactDialog(context, ref, contact: contact),
        trailing: IconButton(
          tooltip: 'Delete contact',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final service = ref.read(contactServiceProvider);
            await service.deleteContact(contact);
            ref.invalidate(contactListProvider);
          },
        ),
      ),
    );
  }
}

/// Shared add/edit dialog — pass [contact] to edit, omit to create.
Future<void> showEditContactDialog(
  BuildContext context,
  WidgetRef ref, {
  Contact? contact,
}) {
  return showDialog(
    context: context,
    builder: (_) => _ContactDialog(contact: contact),
  );
}

class _ContactDialog extends ConsumerStatefulWidget {
  const _ContactDialog({this.contact});

  final Contact? contact;

  @override
  ConsumerState<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends ConsumerState<_ContactDialog> {
  late final _nameController = TextEditingController(text: widget.contact?.name ?? '');
  late final _emailController = TextEditingController(text: widget.contact?.email ?? '');
  late final _notesController = TextEditingController(text: widget.contact?.notes ?? '');
  late ContactRole _role = widget.contact?.role ?? ContactRole.betaReader;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final service = ref.read(contactServiceProvider);
    final existing = widget.contact;
    if (existing == null) {
      await service.createContact(
        name: name,
        role: _role,
        email: _emailController.text.trim(),
        notes: _notesController.text.trim(),
      );
    } else {
      await service.updateContact(
        existing.copyWith(
          name: name,
          role: _role,
          email: _emailController.text.trim(),
          notes: _notesController.text.trim(),
        ),
      );
    }
    ref.invalidate(contactListProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.contact == null ? 'New Contact' : 'Edit Contact'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ContactRole>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: [
                for (final role in ContactRole.values)
                  DropdownMenuItem(value: role, child: Text(role.label)),
              ],
              onChanged: (role) => setState(() => _role = role ?? _role),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
