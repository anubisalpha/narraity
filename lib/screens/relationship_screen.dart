import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile_entry.dart';
import '../models/project.dart';
import '../models/relationship.dart';
import '../state/reference_provider.dart';
import '../state/relationship_provider.dart';

const _nodeSize = 96.0;
const _canvasSize = Size(2400, 1600);

/// Family tree / relationship diagram (PLAN.md "Feature: Family Tree /
/// Relationship Diagram"): nodes are characters pulled from Character
/// Profiles, edges are relationships with a type and optional custom label.
/// The canvas is pan/zoomable; dragging a character node onto another opens
/// the relationship dialog with the dragged character as A and the one it
/// landed on as B (or the existing relationship between them, if there is
/// one) — the dragged node snaps back to its own saved position rather than
/// staying wherever it was dropped, since that gesture's purpose is linking,
/// not moving. Dragging onto empty canvas is an ordinary reposition. The "+"
/// toolbar icon opens the same dialog via two character dropdowns instead,
/// for when drag-and-drop isn't convenient. Either way, edges are managed
/// (edited/deleted) from the side list rather than by tapping the drawn
/// line, which would need precise hit-testing against a painted line.
class RelationshipScreen extends ConsumerWidget {
  const RelationshipScreen({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charactersAsync = ref.watch(characterListProvider(project));
    final relationshipsAsync = ref.watch(relationshipListProvider(project));
    final layoutAsync = ref.watch(relationshipLayoutProvider(project));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relationships'),
        actions: [
          IconButton(
            tooltip: 'New Relationship',
            icon: const Icon(Icons.add_link),
            onPressed: charactersAsync.valueOrNull == null ||
                    charactersAsync.value!.length < 2
                ? null
                : () => _addRelationship(context, ref, charactersAsync.value!),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: switch ((charactersAsync, relationshipsAsync, layoutAsync)) {
        (AsyncError(:final error), _, _) ||
        (_, AsyncError(:final error), _) ||
        (_, _, AsyncError(:final error)) =>
          Center(child: Text('Failed to load relationships: $error')),
        (AsyncData(value: final characters), AsyncData(value: final relationships),
              AsyncData(value: final layout)) =>
          characters.length < 2
              ? const Center(
                  child: Text('Add at least two characters to map a relationship.'))
              : Row(
                  children: [
                    Expanded(
                      child: _Canvas(
                        project: project,
                        characters: characters,
                        relationships: relationships,
                        layout: layout,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 260,
                      child: _RelationshipList(
                        project: project,
                        characters: characters,
                        relationships: relationships,
                      ),
                    ),
                  ],
                ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> _addRelationship(
      BuildContext context, WidgetRef ref, List<ProfileEntry> characters) async {
    final result = await _showRelationshipDialog(context, characters: characters);
    if (result == null) return;
    final service = await ref.read(relationshipServiceProvider(project).future);
    await service.addRelationship(
      characterAId: result.characterAId,
      characterBId: result.characterBId,
      type: result.type,
      label: result.label,
    );
    if (context.mounted) invalidateRelationships(ref, project);
  }
}

class _Canvas extends ConsumerWidget {
  const _Canvas({
    required this.project,
    required this.characters,
    required this.relationships,
    required this.layout,
  });

  final Project project;
  final List<ProfileEntry> characters;
  final List<Relationship> relationships;
  final Map<String, (double, double)> layout;

  /// Deterministic grid fallback for a character with no saved position yet
  /// — stable across rebuilds (index-based), so nodes don't jump around
  /// before the user has ever dragged them.
  Offset _positionFor(int index, String id) {
    final saved = layout[id];
    if (saved != null) return Offset(saved.$1, saved.$2);
    const perRow = 6;
    return Offset(40 + (index % perRow) * 160, 40 + (index ~/ perRow) * 140);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positions = {
      for (var i = 0; i < characters.length; i++)
        characters[i].id: _positionFor(i, characters[i].id),
    };

    return InteractiveViewer(
      constrained: false,
      minScale: 0.3,
      maxScale: 2,
      boundaryMargin: const EdgeInsets.all(200),
      child: SizedBox(
        width: _canvasSize.width,
        height: _canvasSize.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _EdgePainter(
                  characters: characters,
                  relationships: relationships,
                  positions: positions,
                  color: Theme.of(context).colorScheme.outline,
                  textColor: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final character in characters)
              _DraggableNode(
                key: ValueKey(character.id),
                project: project,
                character: character,
                position: positions[character.id]!,
                otherCharacters: [for (final c in characters) if (c.id != character.id) c],
                positions: positions,
                relationships: relationships,
              ),
          ],
        ),
      ),
    );
  }
}

class _DraggableNode extends ConsumerStatefulWidget {
  const _DraggableNode({
    super.key,
    required this.project,
    required this.character,
    required this.position,
    required this.otherCharacters,
    required this.positions,
    required this.relationships,
  });

  final Project project;
  final ProfileEntry character;
  final Offset position;

  /// Every other character on the canvas, for drop-target hit-testing.
  final List<ProfileEntry> otherCharacters;

  /// Every node's current (persisted, pre-drag) position, keyed by character
  /// id — used to test whether a drop lands on top of another node.
  final Map<String, Offset> positions;
  final List<Relationship> relationships;

  @override
  ConsumerState<_DraggableNode> createState() => _DraggableNodeState();
}

class _DraggableNodeState extends ConsumerState<_DraggableNode> {
  Offset? _dragPosition;

  /// The other character whose node the current drag position overlaps, or
  /// null if not currently over anyone — used to drop a relationship rather
  /// than move the node.
  ProfileEntry? _dropTarget(Offset dragPosition) {
    final center = dragPosition + const Offset(_nodeSize / 2, _nodeSize / 2);
    for (final other in widget.otherCharacters) {
      final pos = widget.positions[other.id];
      if (pos == null) continue;
      final rect = Rect.fromLTWH(pos.dx, pos.dy, _nodeSize, _nodeSize);
      if (rect.contains(center)) return other;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final position = _dragPosition ?? widget.position;
    final hovering = _dragPosition == null ? null : _dropTarget(_dragPosition!);

    return Positioned(
      left: position.dx,
      top: position.dy,
      // Not a plain GestureDetector: its PanGestureRecognizer competes with
      // InteractiveViewer's own scale/pan recognizer for the same pointer,
      // and InteractiveViewer wins that arena (confirmed — node drags never
      // moved anything, even before this feature). _ImmediateDragRecognizer
      // claims the pointer synchronously on pointer-down, before
      // InteractiveViewer's movement-triggered recognizer gets a chance to.
      child: RawGestureDetector(
        gestures: {
          _ImmediateDragRecognizer:
              GestureRecognizerFactoryWithHandlers<_ImmediateDragRecognizer>(
            _ImmediateDragRecognizer.new,
            (recognizer) {
              recognizer.onUpdate =
                  (delta) => setState(() => _dragPosition = position + delta);
              recognizer.onEnd = () => _handleDrop(context);
            },
          ),
        },
        child: SizedBox(
          width: _nodeSize,
          height: _nodeSize,
          child: Card(
            shape: hovering == null
                ? null
                : RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                    side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
                  ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_outline, size: 22),
                  const SizedBox(height: 4),
                  Text(
                    widget.character.name,
                    style: Theme.of(context).textTheme.labelSmall,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hovering != null)
                    Text('→ ${hovering.name}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary, fontSize: 9),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleDrop(BuildContext context) async {
    final dragPosition = _dragPosition;
    if (dragPosition == null) return;

    final target = _dropTarget(dragPosition);
    if (target == null) {
      // Ordinary reposition: persist where it landed.
      final service = await ref.read(relationshipServiceProvider(widget.project).future);
      await service.setNodePosition(widget.character.id, dragPosition.dx, dragPosition.dy);
      if (mounted) invalidateRelationships(ref, widget.project);
      return;
    }

    // Dropped on another node: snap back to its persisted position (this
    // gesture creates/edits a relationship, not a move) and open the
    // relationship dialog with the dragged character as A, the character it
    // was dropped onto as B.
    setState(() => _dragPosition = null);

    final existing = widget.relationships.firstWhereOrNull((r) =>
        (r.characterAId == widget.character.id && r.characterBId == target.id) ||
        (r.characterAId == target.id && r.characterBId == widget.character.id));

    if (!context.mounted) return;
    final allCharacters = [widget.character, ...widget.otherCharacters];
    if (existing != null) {
      final result = await _showRelationshipDialog(
        context,
        characters: allCharacters,
        initial: existing,
      );
      if (result == null) return;
      final service = await ref.read(relationshipServiceProvider(widget.project).future);
      await service.saveRelationship(existing.copyWith(type: result.type, label: result.label));
    } else {
      final result = await _showRelationshipDialog(
        context,
        characters: allCharacters,
        presetCharacterAId: widget.character.id,
        presetCharacterBId: target.id,
      );
      if (result == null) return;
      final service = await ref.read(relationshipServiceProvider(widget.project).future);
      await service.addRelationship(
        characterAId: result.characterAId,
        characterBId: result.characterBId,
        type: result.type,
        label: result.label,
      );
    }
    if (mounted) invalidateRelationships(ref, widget.project);
  }
}

/// Claims a pointer for a plain single-finger drag the instant it touches
/// down, rather than waiting to see movement past a touch-slop threshold
/// like [PanGestureRecognizer] does. Needed because a node sits inside
/// [InteractiveViewer], whose own scale/pan recognizer competes for the same
/// pointer and — being also movement-triggered — wins that race often enough
/// that a plain `GestureDetector.onPanUpdate` on the node never fires at
/// all. Resolving the arena synchronously in [addPointer], before
/// InteractiveViewer's recognizer gets a chance to accept, reliably wins
/// instead.
class _ImmediateDragRecognizer extends OneSequenceGestureRecognizer {
  ValueChanged<Offset>? onUpdate;
  VoidCallback? onEnd;

  Offset? _lastPosition;

  @override
  void addPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer);
    resolve(GestureDisposition.accepted);
    _lastPosition = event.position;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      onUpdate?.call(event.position - _lastPosition!);
      _lastPosition = event.position;
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
      onEnd?.call();
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'immediateDrag';
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({
    required this.characters,
    required this.relationships,
    required this.positions,
    required this.color,
    required this.textColor,
  });

  final List<ProfileEntry> characters;
  final List<Relationship> relationships;
  final Map<String, Offset> positions;
  final Color color;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    final center = Offset(_nodeSize / 2, _nodeSize / 2);

    for (final relationship in relationships) {
      final a = positions[relationship.characterAId];
      final b = positions[relationship.characterBId];
      if (a == null || b == null) continue;
      final from = a + center;
      final to = b + center;
      canvas.drawLine(from, to, paint);

      final label = relationship.label.isEmpty
          ? relationship.type.label
          : '${relationship.type.label}: ${relationship.label}';
      final painter = TextPainter(
        text: TextSpan(text: label, style: TextStyle(fontSize: 10, color: textColor)),
        textDirection: TextDirection.ltr,
      )..layout();
      final mid = Offset.lerp(from, to, 0.5)!;
      painter.paint(canvas, mid - Offset(painter.width / 2, painter.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) =>
      oldDelegate.relationships != relationships || oldDelegate.positions != positions;
}

class _RelationshipList extends ConsumerWidget {
  const _RelationshipList({
    required this.project,
    required this.characters,
    required this.relationships,
  });

  final Project project;
  final List<ProfileEntry> characters;
  final List<Relationship> relationships;

  String _nameFor(String id) =>
      characters.firstWhere((c) => c.id == id, orElse: () => characters.first).name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (relationships.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No relationships yet. Use the link icon above to add one.'),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final relationship in relationships)
          ListTile(
            dense: true,
            title: Text('${_nameFor(relationship.characterAId)} ↔ '
                '${_nameFor(relationship.characterBId)}'),
            subtitle: Text(relationship.label.isEmpty
                ? relationship.type.label
                : '${relationship.type.label}: ${relationship.label}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () async {
                final service = await ref.read(relationshipServiceProvider(project).future);
                await service.deleteRelationship(relationship.id);
                if (context.mounted) invalidateRelationships(ref, project);
              },
            ),
            onTap: () => _edit(context, ref, relationship),
          ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Relationship relationship) async {
    final result = await _showRelationshipDialog(
      context,
      characters: characters,
      initial: relationship,
    );
    if (result == null) return;
    final service = await ref.read(relationshipServiceProvider(project).future);
    await service.saveRelationship(
      relationship.copyWith(type: result.type, label: result.label),
    );
    if (context.mounted) invalidateRelationships(ref, project);
  }
}

class _RelationshipDraft {
  const _RelationshipDraft(this.characterAId, this.characterBId, this.type, this.label);

  final String characterAId;
  final String characterBId;
  final RelationshipType type;
  final String label;
}

Future<_RelationshipDraft?> _showRelationshipDialog(
  BuildContext context, {
  required List<ProfileEntry> characters,
  Relationship? initial,
  String? presetCharacterAId,
  String? presetCharacterBId,
}) {
  var characterA = initial?.characterAId ?? presetCharacterAId ?? characters.first.id;
  var characterB = initial?.characterBId ??
      presetCharacterBId ??
      characters.firstWhere((c) => c.id != characterA, orElse: () => characters.last).id;
  var type = initial?.type ?? RelationshipType.family;
  final labelController = TextEditingController(text: initial?.label ?? '');
  final isEditing = initial != null;

  return showDialog<_RelationshipDraft>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(isEditing ? 'Edit Relationship' : 'New Relationship'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isEditing) ...[
              DropdownButtonFormField<String>(
                initialValue: characterA,
                decoration: const InputDecoration(labelText: 'Character A'),
                items: [
                  for (final c in characters) DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (value) => setState(() => characterA = value!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: characterB,
                decoration: const InputDecoration(labelText: 'Character B'),
                items: [
                  for (final c in characters) DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (value) => setState(() => characterB = value!),
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<RelationshipType>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final t in RelationshipType.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (value) => setState(() => type = value!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: labelController,
              decoration: const InputDecoration(labelText: 'Label (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: characterA == characterB
                ? null
                : () => Navigator.pop(context,
                    _RelationshipDraft(characterA, characterB, type, labelController.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
