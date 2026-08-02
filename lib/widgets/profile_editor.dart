import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/content_owner.dart';
import '../models/profile_entry.dart';
import '../services/profile_service.dart';
import '../state/editor_settings_provider.dart';
import '../state/reference_provider.dart';

/// Main-pane editor for one character profile or worldbuilding entry.
///
/// Fields are author-defined: every one can be renamed, removed, or added to,
/// and any can be starred as `quickRef` so the Reference Panel (Phase 2.5)
/// knows what's worth showing at a glance. Saves are debounced like the scene
/// editor rather than needing an explicit save action. Shared between a
/// project and a series (see [ContentOwner]) — the Reference Panel itself
/// is project-only, so `quickRef` is inert but harmless for a series entry.
class ProfileEditor extends ConsumerStatefulWidget {
  const ProfileEditor({
    super.key,
    required this.owner,
    required this.kind,
    required this.entryId,
  });

  final ContentOwner owner;
  final ProfileKind kind;
  final String entryId;

  @override
  ConsumerState<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends ConsumerState<ProfileEditor> {
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();

  /// One controller per field, keyed by field name so renaming a field can
  /// carry its controller (and the caret) across.
  final _fieldControllers = <String, TextEditingController>{};

  ProfileService? _service;
  ProfileEntry? _entry;
  Timer? _saveDebounce;
  bool _dirty = false;

  bool get _isCharacter => widget.kind == ProfileKind.character;

  @override
  void initState() {
    super.initState();
    _load();
    _nameController.addListener(_onChanged);
    _categoryController.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(ProfileEditor old) {
    super.didUpdateWidget(old);
    if (old.entryId != widget.entryId || old.kind != widget.kind) {
      _flushSave();
      _load();
    }
  }

  @override
  void dispose() {
    _flushSave();
    _saveDebounce?.cancel();
    _nameController.dispose();
    _categoryController.dispose();
    for (final controller in _fieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final service = await ref.read(
      (_isCharacter ? characterServiceProvider : worldServiceProvider)(widget.owner)
          .future,
    );
    final entries = await service.list();
    final entry = entries.where((e) => e.id == widget.entryId).firstOrNull;
    if (!mounted || entry == null) return;

    for (final controller in _fieldControllers.values) {
      controller.dispose();
    }
    _fieldControllers.clear();
    for (final field in entry.fields.entries) {
      _fieldControllers[field.key] = TextEditingController(text: field.value)
        ..addListener(_onChanged);
    }

    setState(() {
      _service = service;
      _entry = entry;
    });
    _nameController.text = entry.name;
    _categoryController.text = entry.category ?? '';
    _dirty = false;
  }

  void _onChanged() {
    if (_entry == null) return;
    _dirty = true;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 1), _flushSave);
  }

  Future<void> _flushSave() async {
    _saveDebounce?.cancel();
    final entry = _entry;
    final service = _service;
    if (entry == null || service == null || !_dirty) return;

    final name = _nameController.text.trim();
    final category = _categoryController.text.trim();
    final updated = entry.copyWith(
      name: name.isEmpty ? entry.name : name,
      category: category.isEmpty ? null : category,
      clearCategory: category.isEmpty,
      fields: {
        for (final key in _fieldControllers.keys) key: _fieldControllers[key]!.text,
      },
    );

    await service.save(updated);
    _dirty = false;
    _entry = updated;
    if (mounted) invalidateReferences(ref, widget.owner);
  }

  /// Field edits that change structure (add/rename/remove/star) save straight
  /// away rather than waiting for the debounce — they're deliberate actions,
  /// and the sidebar/Reference Panel should reflect them at once.
  Future<void> _applyStructuralChange(ProfileEntry updated) async {
    final service = _service;
    if (service == null) return;
    await service.save(updated);
    setState(() => _entry = updated);
    _dirty = false;
    if (mounted) invalidateReferences(ref, widget.owner);
  }

  Future<void> _addField() async {
    final entry = _entry;
    if (entry == null) return;

    final name = await _promptForFieldName(title: 'Add field');
    if (name == null || name.trim().isEmpty) return;
    final trimmed = name.trim();
    if (entry.fields.containsKey(trimmed)) {
      _showMessage('There is already a field called "$trimmed".');
      return;
    }

    _fieldControllers[trimmed] = TextEditingController()..addListener(_onChanged);
    await _applyStructuralChange(
      entry.copyWith(fields: {...entry.fields, trimmed: ''}),
    );
  }

  Future<void> _renameField(String oldName) async {
    final entry = _entry;
    if (entry == null) return;

    final name = await _promptForFieldName(title: 'Rename field', initial: oldName);
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == oldName) return;
    if (entry.fields.containsKey(trimmed)) {
      _showMessage('There is already a field called "$trimmed".');
      return;
    }

    // Rebuild in order so renaming doesn't move the field to the end.
    final fields = <String, String>{};
    final controllers = <String, TextEditingController>{};
    for (final key in entry.fields.keys) {
      final isTarget = key == oldName;
      final newKey = isTarget ? trimmed : key;
      fields[newKey] = _fieldControllers[key]?.text ?? entry.fields[key] ?? '';
      controllers[newKey] = _fieldControllers[key]!;
    }
    _fieldControllers
      ..clear()
      ..addAll(controllers);

    await _applyStructuralChange(entry.copyWith(
      fields: fields,
      quickRef: [
        for (final name in entry.quickRef) name == oldName ? trimmed : name,
      ],
    ));
  }

  Future<void> _removeField(String name) async {
    final entry = _entry;
    if (entry == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove "$name"?'),
        content: const Text('The field and anything written in it are removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    _fieldControllers.remove(name)?.dispose();
    final fields = Map<String, String>.from(entry.fields)..remove(name);
    await _applyStructuralChange(entry.copyWith(
      fields: fields,
      quickRef: entry.quickRef.where((q) => q != name).toList(),
    ));
  }

  Future<void> _toggleQuickRef(String name) async {
    final entry = _entry;
    if (entry == null) return;
    final quickRef = entry.quickRef.contains(name)
        ? entry.quickRef.where((q) => q != name).toList()
        : [...entry.quickRef, name];
    await _applyStructuralChange(entry.copyWith(quickRef: quickRef));
  }

  Future<void> _pickImage() async {
    final entry = _entry;
    final service = _service;
    if (entry == null || service == null) return;

    final result = await FilePicker.pickFiles(
      type: FileType.image,
      dialogTitle: 'Choose an image',
      lockParentWindow: true,
    );
    final path = result?.files.single.path;
    if (path == null) return;

    final updated = await service.attachImage(entry, File(path));
    if (!mounted) return;
    setState(() => _entry = updated);
    invalidateReferences(ref, widget.owner);
  }

  Future<void> _removeImage() async {
    final entry = _entry;
    final service = _service;
    if (entry == null || service == null) return;
    final updated = await service.removeImage(entry);
    if (!mounted) return;
    setState(() => _entry = updated);
    invalidateReferences(ref, widget.owner);
  }

  Future<String?> _promptForFieldName({required String title, String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Field name'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    if (entry == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final settings = ref.watch(editorSettingsProvider);
    final bodyStyle = TextStyle(
      fontFamily: settings.fontFamily,
      fontSize: settings.fontSize,
      height: settings.lineHeight,
    );
    final imageFile = _service?.imageFile(entry);
    final hasImage = imageFile != null && imageFile.existsSync();

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ImageBox(
              imageFile: hasImage ? imageFile : null,
              onPick: _pickImage,
              onRemove: hasImage ? _removeImage : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameController,
                    style: Theme.of(context).textTheme.headlineSmall,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: _isCharacter ? 'Character name' : 'Entry name',
                    ),
                  ),
                  if (!_isCharacter)
                    TextField(
                      controller: _categoryController,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Category (Location, Faction, Magic…)',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 32),
        for (final name in entry.fields.keys)
          _FieldRow(
            name: name,
            controller: _fieldControllers[name]!,
            isQuickRef: entry.quickRef.contains(name),
            bodyStyle: bodyStyle,
            onToggleQuickRef: () => _toggleQuickRef(name),
            onRename: () => _renameField(name),
            onRemove: () => _removeField(name),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add field'),
            onPressed: _addField,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Starred fields show at a glance in the Reference Panel while you write.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ImageBox extends StatelessWidget {
  const _ImageBox({required this.imageFile, required this.onPick, this.onRemove});

  final File? imageFile;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onPick,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).dividerColor),
              image: imageFile == null
                  ? null
                  : DecorationImage(image: FileImage(imageFile!), fit: BoxFit.cover),
            ),
            child: imageFile != null
                ? null
                : const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined),
                        SizedBox(height: 4),
                        Text('Add image'),
                      ],
                    ),
                  ),
          ),
        ),
        if (onRemove != null)
          TextButton(onPressed: onRemove, child: const Text('Remove image')),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.name,
    required this.controller,
    required this.isQuickRef,
    required this.bodyStyle,
    required this.onToggleQuickRef,
    required this.onRename,
    required this.onRemove,
  });

  final String name;
  final TextEditingController controller;
  final bool isQuickRef;
  final TextStyle bodyStyle;
  final VoidCallback onToggleQuickRef;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(name, style: Theme.of(context).textTheme.titleSmall),
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: isQuickRef ? 'Remove from quick reference' : 'Show at a glance',
                icon: Icon(isQuickRef ? Icons.star : Icons.star_border),
                color: isQuickRef ? Theme.of(context).colorScheme.primary : null,
                onPressed: onToggleQuickRef,
              ),
              const Spacer(),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, size: 18),
                onSelected: (action) => action == 'rename' ? onRename() : onRemove(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename field')),
                  PopupMenuItem(value: 'remove', child: Text('Remove field')),
                ],
              ),
            ],
          ),
          TextField(
            controller: controller,
            style: bodyStyle,
            maxLines: null,
            minLines: 1,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}
