import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';

class InlinePreview extends StatefulWidget {
  final ui.Image image;
  final VoidCallback onTap;
  const InlinePreview({super.key, required this.image, required this.onTap});
  @override
  State<InlinePreview> createState() => _InlinePreviewState();
}

class _InlinePreviewState extends State<InlinePreview> {
  double scale = 1;
  Offset offset = Offset.zero;
  Size size = Size.zero;
  void transform(Offset oldFocus, Offset newFocus, double factor) {
    final next = (scale * factor).clamp(1.0, 8.0);
    final ratio = next / scale;
    final center = size.center(Offset.zero);
    setState(() {
      offset = newFocus - center - (oldFocus - center - offset) * ratio;
      scale = next;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (c, b) {
      size = b.biggest;
      return ClipRect(
        child: GestureDetector(
          onTap: widget.onTap,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              _TwoFingerGesture:
                  GestureRecognizerFactoryWithHandlers<_TwoFingerGesture>(
                    _TwoFingerGesture.new,
                    (r) => r.onTransform = transform,
                  ),
            },
            child: Transform.translate(
              offset: offset,
              child: Transform.scale(
                scale: scale,
                child: RawImage(
                  image: widget.image,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Wait for two pointers before claiming the gesture, leaving one-finger scrolling
/// and taps to the parent. Both local focal translation and span are preserved.
class _TwoFingerGesture extends OneSequenceGestureRecognizer {
  final points = <int, Offset>{};
  void Function(Offset, Offset, double)? onTransform;
  bool accepted = false;
  (Offset, double)? pendingGeometry;
  int? frame;
  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    points[event.pointer] = event.localPosition;
    if (points.length == 2) {
      accepted = true;
      resolve(GestureDisposition.accepted);
    }
  }

  (Offset, double)? get geometry {
    if (points.length < 2) return null;
    final p = points.values.take(2).toList();
    return ((p[0] + p[1]) / 2, (p[0] - p[1]).distance);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent && points.containsKey(event.pointer)) {
      pendingGeometry ??= geometry;
      points[event.pointer] = event.localPosition;
      frame ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
        frame = null;
        final before = pendingGeometry, after = geometry;
        pendingGeometry = null;
        if (accepted && before != null && after != null) {
          onTransform?.call(
            before.$1,
            after.$1,
            before.$2 > .001 ? after.$2 / before.$2 : 1,
          );
        }
      });
    }

    if (event is PointerUpEvent || event is PointerCancelEvent) {
      points.remove(event.pointer);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    points.remove(pointer);
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    if (!accepted) resolve(GestureDisposition.rejected);
    accepted = false;
  }

  @override
  void dispose() {
    if (frame != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(frame!);
    }
    super.dispose();
  }

  @override
  String get debugDescription => 'two-finger preview';
}
