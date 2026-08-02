import 'package:flutter/material.dart';

/// Thin draggable divider that resizes an adjacent panel — the project
/// shell's manuscript sidebar, the series screen's own sidebar, and the
/// Reference Panel all use this, each translating the raw drag delta to its
/// own width/fraction change (and sign: the Reference Panel widens when
/// dragged left, so its caller inverts the delta).
class ResizeHandle extends StatelessWidget {
  const ResizeHandle({
    super.key,
    required this.onDrag,
    required this.onDragEnd,
  });

  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        onHorizontalDragEnd: (_) => onDragEnd(),
        // The visible divider is 1px, but the grab area is padded out to 8px:
        // a 1px drag target is painful to hit.
        child: const SizedBox(
          width: 8,
          child: Center(child: VerticalDivider(width: 1)),
        ),
      ),
    );
  }
}
