import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'model.dart';

Path coverShape(Rect r, CardDocument doc) {
  final type = doc.text('coverShape');
  final params = mapv(mapv(doc.data['coverShapeParameters'])[type]);
  double n(String key, [double fallback = 0]) =>
      numv(params[key], doc.n(key, fallback));
  final radius = n('coverCornerRadius')
      .clamp(0, math.min(r.width, r.height) / 2)
      .toDouble();
  if (type == 'ellipse' || type.isEmpty && n('coverCornerRadius') == 180) {
    return Path()..addOval(r);
  }
  if (type == 'elliptical') {
    return Path()..addRRect(
      RRect.fromRectAndRadius(
        r,
        Radius.elliptical(
          n('cornerRadiusX', 40).clamp(0, r.width / 2).toDouble(),
          n('cornerRadiusY', 20).clamp(0, r.height / 2).toDouble(),
        ),
      ),
    );
  }
  if (type == 'quadratic' || type == 'scoop') {
    // Construct one corner in local coordinates, then rotate it around the rect.
    final p = Path();
    final origins = [
      Offset(r.left, r.top),
      Offset(r.right, r.top),
      Offset(r.right, r.bottom),
      Offset(r.left, r.bottom),
    ];
    Offset transform(int i, double x, double y) =>
        origins[i] +
        switch (i) {
          0 => Offset(x, y),
          1 => Offset(-y, x),
          2 => Offset(-x, -y),
          _ => Offset(y, -x),
        };
    final tension = n('cornerTension', 0).clamp(0, 1);
    for (var i = 0; i < 4; i++) {
      final start = transform(i, 0, radius), end = transform(i, radius, 0);
      if (i == 0) {
        p.moveTo(start.dx, start.dy);
      } else {
        p.lineTo(start.dx, start.dy);
      }
      if (type == 'scoop') {
        // Quarter-circle centered on the outer corner, cutting inward.
        p.arcToPoint(end, radius: Radius.circular(radius), clockwise: false);
      } else {
        final control = transform(i, radius * tension, radius * tension);
        p.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
      }
    }
    return p..close();
  }
  if (type == 'continuous') {
    return ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    ).getOuterPath(r);
  }
  if (type == 'bevel') {
    return BeveledRectangleBorder(borderRadius: BorderRadius.circular(radius))
        .getOuterPath(r);
  }
  if (type == 'superellipse') {
    final exponent = n('coverExponent', 4).clamp(1, 12);
    final p = Path();
    for (int i = 0; i <= 240; i++) {
      final t = i / 240 * math.pi * 2,
          c = math.cos(t),
          s = math.sin(t),
          x =
              r.center.dx +
              r.width / 2 * c.sign * math.pow(c.abs(), 2 / exponent),
          y =
              r.center.dy +
              r.height / 2 * s.sign * math.pow(s.abs(), 2 / exponent);
      if (i == 0) {
        p.moveTo(x.toDouble(), y.toDouble());
      } else {
        p.lineTo(x.toDouble(), y.toDouble());
      }
    }
    return p..close();
  }
  if (type == 'concave') {
    return Path()
      ..moveTo(r.left + radius, r.top)
      ..lineTo(r.right - radius, r.top)
      ..quadraticBezierTo(
        r.right - radius,
        r.top + radius,
        r.right,
        r.top + radius,
      )
      ..lineTo(r.right, r.bottom - radius)
      ..quadraticBezierTo(
        r.right - radius,
        r.bottom - radius,
        r.right - radius,
        r.bottom,
      )
      ..lineTo(r.left + radius, r.bottom)
      ..quadraticBezierTo(
        r.left + radius,
        r.bottom - radius,
        r.left,
        r.bottom - radius,
      )
      ..lineTo(r.left, r.top + radius)
      ..quadraticBezierTo(
        r.left + radius,
        r.top + radius,
        r.left + radius,
        r.top,
      )
      ..close();
  }
  Radius corner(String k) => Radius.circular(
    n(k, radius).clamp(0, math.min(r.width, r.height) / 2).toDouble(),
  );
  return Path()..addRRect(
    type == 'individual'
        ? RRect.fromRectAndCorners(
            r,
            topLeft: corner('cornerTL'),
            topRight: corner('cornerTR'),
            bottomLeft: corner('cornerBL'),
            bottomRight: corner('cornerBR'),
          )
        : RRect.fromRectAndRadius(r, Radius.circular(radius)),
  );
}

class CoverShapeIcon extends StatelessWidget {
  final String type;
  const CoverShapeIcon(this.type, {super.key});
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(22, 22),
    painter: _ShapePainter(type, Theme.of(context).colorScheme.onSurface),
  );
}

class _ShapePainter extends CustomPainter {
  final String type;
  final Color color;
  _ShapePainter(this.type, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final doc = CardDocument.fresh();
    doc.data.addAll({
      'coverShape': type,
      'coverCornerRadius': 7.0,
      'cornerTL': 8.0,
      'cornerTR': 1.0,
      'cornerBL': 1.0,
      'cornerBR': 8.0,
    });
    canvas.drawPath(
      coverShape(Offset.zero & size, doc),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_ShapePainter old) =>
      old.type != type || old.color != color;
}
