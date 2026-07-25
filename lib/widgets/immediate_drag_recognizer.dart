import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// Claims a pointer for a plain single-finger drag the instant it touches
/// down, rather than waiting to see movement past a touch-slop threshold
/// like [PanGestureRecognizer] does. Needed whenever a draggable widget sits
/// inside an [InteractiveViewer] (or anything else with its own
/// movement-triggered recognizer) — the ancestor's recognizer competes for
/// the same pointer and, being also movement-triggered, can win that race.
/// Confirmed on the Relationship Diagram's canvas: a plain
/// `GestureDetector.onPanUpdate` on a node never fired at all, because
/// `InteractiveViewer`'s own scale/pan recognizer won every time. Resolving
/// the arena synchronously in [addPointer], before the ancestor's recognizer
/// gets a chance to accept, reliably wins instead.
///
/// Reports raw absolute (global, screen-space) pointer positions rather than
/// deltas — the caller should convert each one through
/// `RenderBox.globalToLocal` and anchor it to a grab offset captured on
/// [onDown]. A delta computed here, in screen pixels, would be wrong the
/// moment the ancestor view is panned or zoomed (this was a real,
/// separately-diagnosed bug on the Relationship Diagram: dragging felt
/// laggy because a screen-pixel delta doesn't equal the same delta in a
/// zoomed canvas's local coordinate space).
class ImmediateDragRecognizer extends OneSequenceGestureRecognizer {
  ValueChanged<Offset>? onDown;
  ValueChanged<Offset>? onMove;
  VoidCallback? onEnd;

  @override
  void addPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer);
    resolve(GestureDisposition.accepted);
    onDown?.call(event.position);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      onMove?.call(event.position);
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
