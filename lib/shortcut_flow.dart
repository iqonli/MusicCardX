import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Measures real button sizes, uses one row when possible, otherwise two
/// independently spaced rows. The last pair stays together (new/manage).
class ShortcutFlow extends MultiChildRenderObjectWidget {
  final double viewportWidth;
  final bool keepLastPair;
  const ShortcutFlow({
    super.key,
    required this.viewportWidth,
    required this.keepLastPair,
    required super.children,
  });
  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderShortcutFlow(viewportWidth, keepLastPair);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderShortcutFlow renderObject,
  ) {
    renderObject.update(viewportWidth, keepLastPair);
  }
}

class _ShortcutData extends ContainerBoxParentData<RenderBox> {}

class RenderShortcutFlow extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  double width;
  bool keepPair;
  RenderShortcutFlow(this.width, this.keepPair);
  void update(double value, bool pair) {
    if (value != width || pair != keepPair) {
      width = value;
      keepPair = pair;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _ShortcutData();
    }
  }

  @override
  void performLayout() {
    final children = <RenderBox>[];
    RenderBox? child = firstChild;
    while (child != null) {
      child.layout(const BoxConstraints(), parentUsesSize: true);
      children.add(child);
      child = childAfter(child);
    }
    if (children.isEmpty) {
      size = constraints.constrain(Size.zero);
      return;
    }
    double rowWidth(int a, int b) =>
        children.sublist(a, b).fold<double>(0, (sum, c) => sum + c.size.width) +
        (b - a - 1).clamp(0, children.length) * 8;
    final full = rowWidth(0, children.length);
    int split = children.length;
    if (full > width && children.length > 1) {
      double best = double.infinity;
      final end = keepPair && children.length > 2
          ? children.length - 2
          : children.length - 1;
      for (int i = 1; i <= end; i++) {
        final a = rowWidth(0, i), b = rowWidth(i, children.length);
        final score = a > b ? a : b;
        if (score < best) {
          best = score;
          split = i;
        }
      }
    }
    double y = 0, maxWidth = 0;
    for (final range in [
      (0, split),
      if (split < children.length) (split, children.length),
    ]) {
      double x = 0, height = 0;
      for (int i = range.$1; i < range.$2; i++) {
        final c = children[i];
        (c.parentData as ContainerBoxParentData<RenderBox>).offset = Offset(
          x,
          y,
        );
        x += c.size.width + 8;
        if (c.size.height > height) height = c.size.height;
      }
      if (x - 8 > maxWidth) maxWidth = x - 8;
      y += height;
    }
    size = constraints.constrain(Size(maxWidth, y));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
