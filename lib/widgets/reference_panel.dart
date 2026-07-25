import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile_entry.dart';
import '../models/project.dart';
import '../services/profile_service.dart';
import '../state/reference_panel_provider.dart';
import '../state/reference_provider.dart';

/// The Reference Panel (PLAN.md differentiator): compact cards for pinned
/// entries and for whatever the open scene mentions, showing only the fields
/// the author starred as quickRef — contextual reference *while writing*,
/// never a navigation away from the manuscript.
class ReferencePanel extends ConsumerWidget {
  const ReferencePanel({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentAsync = ref.watch(referencePanelContentProvider(project));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
          child: Row(
            children: [
              Text('Reference', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              IconButton(
                tooltip: 'Hide panel',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () =>
                    ref.read(referencePanelVisibleProvider.notifier).toggle(),
              ),
            ],
          ),
        ),
        Expanded(
          child: contentAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Failed to load references: $err'),
            ),
            data: (content) {
              if (content.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Pin a character or world entry from the sidebar, or type '
                    '@ in a scene to mention one — its at-a-glance fields '
                    'appear here while you write.',
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                children: [
                  for (final entry in content.pinned)
                    _ReferenceCard(project: project, entry: entry, pinned: true),
                  if (content.mentioned.isNotEmpty && content.pinned.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                      child: Text('In this scene',
                          style: Theme.of(context).textTheme.labelSmall),
                    ),
                  for (final entry in content.mentioned)
                    _ReferenceCard(project: project, entry: entry, pinned: false),
                  for (final name in content.unresolved)
                    _UnresolvedMentionCard(project: project, name: name),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ReferenceCard extends ConsumerWidget {
  const _ReferenceCard({
    required this.project,
    required this.entry,
    required this.pinned,
  });

  final Project project;
  final ProfileEntry entry;
  final bool pinned;

  bool get _isCharacter => entry.id.startsWith('char-');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serviceAsync = ref.watch(
        (_isCharacter ? characterServiceProvider : worldServiceProvider)(project));
    final service = serviceAsync.valueOrNull;
    final imageFile = service?.imageFile(entry);
    final hasImage = imageFile != null && imageFile.existsSync();

    final quickRefFields = [
      for (final name in entry.quickRef)
        if (entry.fields.containsKey(name)) name,
    ];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  foregroundImage: hasImage ? FileImage(imageFile) : null,
                  child: hasImage
                      ? null
                      : Icon(_isCharacter ? Icons.person_outline : Icons.public,
                          size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.name,
                          style: Theme.of(context).textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis),
                      if (entry.category != null)
                        Text(entry.category!,
                            style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: pinned ? 'Unpin' : 'Pin to panel',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 16,
                  ),
                  onPressed: () => ref
                      .read(pinnedReferencesProvider(project).notifier)
                      .toggle(entry.id),
                ),
                IconButton(
                  tooltip: 'Open full profile',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.open_in_full, size: 15),
                  onPressed: () =>
                      ref.read(openReferenceProvider.notifier).state =
                          ReferenceSelection(
                    _isCharacter ? ReferenceKind.character : ReferenceKind.world,
                    entry.id,
                  ),
                ),
              ],
            ),
            if (quickRefFields.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'No quick-reference fields — star some on the profile.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              for (final field in quickRefFields)
                _QuickRefField(
                  project: project,
                  entry: entry,
                  fieldName: field,
                  isCharacter: _isCharacter,
                ),
          ],
        ),
      ),
    );
  }
}

/// One starred field on a card. Read-only until tapped; then it becomes an
/// inline editor saving on a debounce — the PLAN.md "quick-edit without
/// leaving the editor" behaviour.
class _QuickRefField extends ConsumerStatefulWidget {
  const _QuickRefField({
    required this.project,
    required this.entry,
    required this.fieldName,
    required this.isCharacter,
  });

  final Project project;
  final ProfileEntry entry;
  final String fieldName;
  final bool isCharacter;

  @override
  ConsumerState<_QuickRefField> createState() => _QuickRefFieldState();
}

class _QuickRefFieldState extends ConsumerState<_QuickRefField> {
  bool _editing = false;
  TextEditingController? _controller;
  Timer? _saveDebounce;

  /// Resolved when editing starts, so [_flushSave] never needs `ref` — it can
  /// be called from [dispose], where reading providers isn't safe.
  ProfileService? _service;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _flushSave();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _startEditing() async {
    _service ??= await ref.read(
      (widget.isCharacter ? characterServiceProvider : worldServiceProvider)(
              widget.project)
          .future,
    );
    if (!mounted) return;
    _controller ??= TextEditingController();
    _controller!.text = widget.entry.fields[widget.fieldName] ?? '';
    setState(() => _editing = true);
  }

  void _onChanged(String _) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 1), _flushSave);
  }

  Future<void> _flushSave() async {
    _saveDebounce?.cancel();
    final controller = _controller;
    final service = _service;
    if (controller == null || service == null) return;

    // Captured before any await: the controller may be disposed by the time
    // the save actually runs.
    final text = controller.text;
    if (text == (widget.entry.fields[widget.fieldName] ?? '')) return;

    await service.save(widget.entry.copyWith(
      fields: {...widget.entry.fields, widget.fieldName: text},
    ));
    if (mounted) invalidateReferences(ref, widget.project);
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.entry.fields[widget.fieldName] ?? '';

    return Padding(
      padding: const EdgeInsets.only(top: 6, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.fieldName, style: Theme.of(context).textTheme.labelSmall),
          if (_editing)
            Focus(
              onFocusChange: (hasFocus) {
                if (!hasFocus) {
                  _flushSave();
                  setState(() => _editing = false);
                }
              },
              child: TextField(
                controller: _controller,
                autofocus: true,
                maxLines: null,
                style: Theme.of(context).textTheme.bodySmall,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: _onChanged,
              ),
            )
          else
            InkWell(
              onTap: _startEditing,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  value.isEmpty ? '—' : value,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A `[[Name]]` in the scene that matches no profile — either a typo, a
/// renamed entry, or a character who doesn't have a profile yet. Offer to
/// create one rather than just reporting the miss.
class _UnresolvedMentionCard extends ConsumerWidget {
  const _UnresolvedMentionCard({required this.project, required this.name});

  final Project project;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            const Icon(Icons.help_outline, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text('No profile named "$name"',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis),
            ),
            TextButton(
              child: const Text('Create'),
              onPressed: () async {
                final service =
                    await ref.read(characterServiceProvider(project).future);
                final created = await service.create(name: name);
                invalidateReferences(ref, project);
                ref.read(openReferenceProvider.notifier).state =
                    ReferenceSelection(ReferenceKind.character, created.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}
