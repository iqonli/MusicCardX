import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'model.dart';
import 'font_style.dart';
import 'seed.dart';
import 'palette_tools.dart';
import 'cover_shape.dart';

class RenderedCard {
  final ui.Image image;
  final Size size;
  final int milliseconds;
  final String seed;
  RenderedCard(this.image, this.size, this.milliseconds, this.seed);
  Future<Uint8List> png() async =>
      (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List();
}

class _Text {
  final List<TextPainter> parts;
  final double spacing;
  final Size size;
  _Text(this.parts, this.spacing, this.size);
  void paint(Canvas canvas, Offset origin) {
    double x = origin.dx;
    for (final p in parts) {
      p.paint(canvas, Offset(x, origin.dy));
      x += p.width + spacing;
    }
  }

  void dispose() {
    for (final p in parts) {
      p.dispose();
    }
  }
}

const int maxOutputSide = 32768;
const int maxOutputPixels = 100000000;

bool exceedsOutputLimits(int width, int height) =>
    width > maxOutputSide ||
    height > maxOutputSide ||
    width * height > maxOutputPixels;

class RenderCancelledException implements Exception {
  const RenderCancelledException();
  @override
  String toString() => '已取消大尺寸图片生成。';
}

class CardRenderer {
  final ChineseConverter chinese;
  final FontRegistry fonts;
  CardRenderer(this.chinese, this.fonts);
  Future<RenderedCard> render(
    CardDocument doc, {
    ui.Image? cover,
    double? scaleOverride,
    Future<bool> Function(int width, int height)? onOversizedOutput,
  }) async {
    final watch = Stopwatch()..start();
    final ly = doc.lyrics;
    final scale = scaleOverride ?? doc.n('exportScale', 1);
    final palette = await _palette(doc, cover);
    final rainbow = await _rainbow(doc, cover, palette);
    final solid = resolveColor(
      doc.text('solidHex'),
      const Color(0xfffafafa),
      rainbow,
    );
    final bright = doc.text('backgroundStyle') == 'solid'
        ? luminance(solid)
        : palette.map(luminance).reduce((a, b) => a + b) / palette.length;
    final base = doc.text('autoColorMode') == 'black'
        ? const Color(0xff121212)
        : doc.text('autoColorMode') == 'white'
        ? const Color(0xfffafafa)
        : bright > .5
        ? const Color(0xff121212)
        : const Color(0xfffafafa);
    final texts = <String, _Text>{};
    final converted = <String, String>{};
    final all = <Map<String, dynamic>>[...doc.styles.values.map(mapv), ly];
    String specKey(Map<String, dynamic> s) =>
        '${s['font']}:${s['weight']}:${s['bold']}:${s['italic']}';
    final specs = <String, LoadedFont>{};
    for (final s in all) {
      if (specs.containsKey(specKey(s))) continue;
      specs[specKey(s)] = await fonts.resolve(
        '${s['font'] ?? ''}',
        bold: s['bold'] == true,
        weight: s['weight'] is num ? (s['weight'] as num).toInt() : null,
        italic: s['italic'] == true,
      );
    }
    final resources = <_Text>[];
    _Text make(String text, Map<String, dynamic> s, {double? alpha}) {
      final c = opacity(
        resolveColor('${s['colorHex'] ?? ''}', base, rainbow),
        alpha ?? s['opacity'],
      );
      final spec = specs[specKey(s)]!;
      final style = TextStyle(
        fontSize: numv(s['size'], 28),
        fontFamily: spec.family ?? 'Roboto',
        fontWeight: spec.fontWeight,
        fontVariations: spec.variations,
        fontStyle: spec.italic ? FontStyle.italic : FontStyle.normal,
        foreground: Paint()
          ..color = c
          ..isAntiAlias = true,
        height: 1.2,
      );
      final native = s['letterSpacing'] == '' || s['letterSpacing'] == null;
      final parts = (native ? [text] : text.characters.toList())
          .map(
            (part) => TextPainter(
              text: TextSpan(text: part, style: style),
              textDirection: TextDirection.ltr,
            )..layout(),
          )
          .toList();
      final spacing = native ? 0.0 : numv(s['letterSpacing']);
      double advance = 0, maxRight = 0, height = 0;
      for (final p in parts) {
        maxRight = math.max(maxRight, advance + p.width);
        height = math.max(height, p.height);
        advance += p.width + spacing;
      }
      final t = _Text(parts, spacing, Size(maxRight, height));
      resources.add(t);
      return t;
    }

    try {
      for (final k in styleLabels.keys) {
        final s = mapv(doc.styles[k]);
        final text = chinese.convert(
          doc.evaluate('${s['text'] ?? ''}'),
          doc.text('textOpenCCMode'),
        );
        converted[k] = text;
        texts[k] = make(text, s);
      }
      final lyricText = chinese
          .convert(
            doc.evaluate('${ly['text'] ?? ''}'),
            doc.text('lyricsOpenCCMode'),
          )
          .replaceAll('\r\n', '\n');
      final lines = ly['enabled'] == true
          ? lyricText.split('\n').map((l) => make(l, ly)).toList()
          : <_Text>[];
      final naturalL = lines.fold(
        0.0,
        (double a, b) => math.max(a, b.size.width),
      );
      final lyricW = lines.isEmpty
          ? 0.0
          : (numv(ly['containerWidth']) > 0
                ? numv(ly['containerWidth'])
                : naturalL);
      final lyricEnabled = ly['enabled'] == true && lyricW > 0;
      final divider = lyricEnabled && ly['dividerEnabled'] == true;
      final lineWidth = divider ? numv(ly['dividerThickness'], 1) : 0.0;
      final shift = lyricEnabled
          ? lyricW +
                (divider
                    ? numv(ly['dividerLeftGap']) +
                          lineWidth +
                          numv(ly['dividerRightGap'])
                    : numv(ly['rightGap']))
          : 0.0;
      final coverW = cover == null
          ? 0.0
          : (doc.text('irregularCoverMode') == 'tile'
                ? 360 * cover.width / cover.height
                : 360.0);
      final coverX = 20 + shift,
          labelX = cover == null ? coverX : coverX + coverW + 20;
      double blurPad(Map<String, dynamic> s) =>
          numv(s['blurOpacity']) > 0 ? numv(s['blurStrength']) * .7 : 0;
      final labelW = math.max(
        100.0,
        ['titleLabel', 'artistLabel', 'albumLabel']
            .map(
              (k) => texts[k]!.size.width + blurPad(mapv(doc.styles[k])) + 20,
            )
            .reduce(math.max),
      );
      final valueX = labelX + labelW;
      double rowHeight(String a, String b) =>
          math.max(40, math.max(texts[a]!.size.height, texts[b]!.size.height));
      final titleH = rowHeight('titleLabel', 'titleValue'),
          artistH = rowHeight('artistLabel', 'artistValue'),
          albumH = rowHeight('albumLabel', 'albumValue');
      final hasMeta = converted['metaValue']!.trim().isNotEmpty,
          metaH = math.max(28.0, texts['metaValue']!.size.height);
      final totalH =
          titleH + 40 + artistH + 40 + albumH + (hasMeta ? 8 + metaH : 0);
      final titleY = (400 - totalH) / 2,
          artistY = titleY + titleH + 40,
          albumY = artistY + artistH + 40;
      final width = math.max(
        cover == null ? 420 + shift : 800 + coverW - 360 + shift,
        math.max(
              labelX + labelW,
              [
                ...['titleValue', 'artistValue', 'albumValue', 'metaValue'].map(
                  (k) =>
                      valueX +
                      texts[k]!.size.width +
                      blurPad(mapv(doc.styles[k])),
                ),
                labelX +
                    texts['watermark']!.size.width +
                    blurPad(mapv(doc.styles['watermark'])),
              ].reduce(math.max),
            ) +
            44,
      );
      final pixelW = (width * scale).ceil(), pixelH = (400 * scale).ceil();
      // Warn before native allocation. The user may explicitly accept the
      // memory cost; output quality is never silently reduced.
      if (exceedsOutputLimits(pixelW, pixelH)) {
        if (onOversizedOutput == null ||
            !await onOversizedOutput(pixelW, pixelH)) {
          throw const RenderCancelledException();
        }
      }
      final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
      canvas.scale(scale);
      final bounds = Rect.fromLTWH(0, 0, width, 400);
      _background(canvas, bounds, doc, palette, solid, cover, scale);
      void styled(
        _Text text,
        Map<String, dynamic> s,
        Offset offset, {
        Rect? clip,
      }) {
        canvas.save();
        if (clip != null) canvas.clipRect(clip);
        final strength = numv(s['blurStrength']), a = numv(s['blurOpacity']);
        if (strength > 0 && a > 0) {
          final glow = make(
            text.parts.map((p) => p.text!.toPlainText()).join(),
            s,
            alpha: 255,
          );
          canvas.saveLayer(
            bounds.inflate(strength * 2),
            Paint()
              ..imageFilter = ui.ImageFilter.blur(
                sigmaX: strength * .35,
                sigmaY: strength * .35,
              )
              ..color = Colors.white.withValues(alpha: a / 255),
          );
          glow.paint(canvas, offset);
          canvas.restore();
        }
        text.paint(canvas, offset);
        canvas.restore();
      }

      if (lyricEnabled) {
        final step = numv(ly['lineGap'], 40),
            top = numv(ly['topPadding']),
            bottom = numv(ly['bottomPadding']);
        final blockH = lines.isEmpty
            ? 0.0
            : (lines.length - 1) * step + lines.last.size.height;
        final areaH = math.max(0.0, 360 - top - bottom), free = areaH - blockH;
        final start =
            20 +
            top +
            (ly['yAlign'] == 'center'
                ? free / 2
                : ly['yAlign'] == 'bottom'
                ? free
                : 0.0);
        final clip = Rect.fromLTWH(20, 20 + top, lyricW, areaH);
        for (int i = 0; i < lines.length; i++) {
          final t = lines[i];
          final x =
              20 +
              (ly['xAlign'] == 'center'
                  ? (lyricW - t.size.width) / 2
                  : ly['xAlign'] == 'right'
                  ? lyricW - t.size.width
                  : 0.0);
          styled(t, ly, Offset(x, start + i * step), clip: clip);
        }
        if (divider) {
          final x = 20 + lyricW + numv(ly['dividerLeftGap']),
              y = 20 + numv(ly['dividerTopPadding']),
              h = math.max(
                0.0,
                360 -
                    numv(ly['dividerTopPadding']) -
                    numv(ly['dividerBottomPadding']),
              );
          final rect = Rect.fromLTWH(x, y, lineWidth, h);
          canvas.drawRect(
            rect,
            Paint()
              ..shader = ui.Gradient.linear(
                Offset(x, y),
                Offset(x, y + h),
                ['Top', 'Middle', 'Bottom']
                    .map(
                      (k) => opacity(
                        resolveColor(
                          '${ly['divider${k}Hex'] ?? ''}',
                          base,
                          rainbow,
                        ),
                        ly['divider${k}Opacity'],
                      ),
                    )
                    .toList(),
                [0, .5, 1],
              ),
          );
        }
      }
      if (cover != null) {
        final rect = Rect.fromLTWH(coverX, 20, coverW, 360);
        final path = coverShape(rect, doc);
        paintCoverShadow(
          canvas,
          path,
          doc.n('coverShadowDepth').toDouble(),
          doc.n('coverShadowOpacity').toDouble(),
        );
        canvas.save();
        canvas.clipPath(path);
        _cover(canvas, cover, rect, .5);
        canvas.restore();
      }
      void draw(String k, double x, double y) {
        final h = k.startsWith('title')
            ? titleH
            : k.startsWith('artist')
            ? artistH
            : k == 'metaValue'
            ? metaH
            : albumH;
        final free = h - texts[k]!.size.height;
        final align = doc.text('textAlignMode');
        styled(
          texts[k]!,
          mapv(doc.styles[k]),
          Offset(
            x,
            y +
                (align == 'top'
                    ? 0
                    : align == 'bottom'
                    ? free
                    : free / 2),
          ),
        );
      }

      draw('titleLabel', labelX, titleY);
      draw('titleValue', valueX, titleY);
      draw('artistLabel', labelX, artistY);
      draw('artistValue', valueX, artistY);
      draw('albumLabel', labelX, albumY);
      draw('albumValue', valueX, albumY);
      if (hasMeta) draw('metaValue', valueX, albumY + albumH + 8);
      styled(
        texts['watermark']!,
        mapv(doc.styles['watermark']),
        Offset(labelX, 380 - texts['watermark']!.size.height),
      );
      final picture = recorder.endRecording();
      try {
        final image = await picture.toImage(pixelW, pixelH);
        return RenderedCard(
          image,
          Size(pixelW.toDouble(), pixelH.toDouble()),
          watch.elapsedMilliseconds,
          doc.text('seed'),
        );
      } finally {
        picture.dispose();
      }
    } finally {
      for (final t in resources) {
        t.dispose();
      }
    }
  }

  void _cover(Canvas c, ui.Image img, Rect dst, double position) {
    final srcRatio = img.width / img.height, dstRatio = dst.width / dst.height;
    late Rect src;
    if (srcRatio > dstRatio) {
      final w = img.height * dstRatio;
      src = Rect.fromLTWH(
        (img.width - w) * position,
        0,
        w,
        img.height.toDouble(),
      );
    } else {
      final h = img.width / dstRatio;
      src = Rect.fromLTWH(
        0,
        (img.height - h) * position,
        img.width.toDouble(),
        h,
      );
    }
    c.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.high);
  }

  double _sigma(double strength, double base, double factor) => math.sqrt(
    math.pow((base + math.min(100, strength) * factor) / 3, 2) +
        math.max(0, strength - 100) /
            100 *
            math.pow((base + 100 * factor) / 3, 2),
  );
  void _background(
    Canvas c,
    Rect r,
    CardDocument doc,
    List<Color> p,
    Color solid,
    ui.Image? cover,
    double scale,
  ) {
    final mode = doc.text('backgroundStyle');
    if (mode == 'solid') {
      c.drawRect(r, Paint()..color = solid);
      return;
    }
    if (mode == 'blur' && cover != null) {
      final sigma = _sigma(doc.n('blurStrength'), 8, .72);
      c.saveLayer(
        r,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.clamp,
          ),
      );
      _cover(c, cover, r, doc.n('blurBackgroundCropPosition') / 100);
      c.restore();
      c.drawRect(r, Paint()..color = const Color(0x12ffffff));
      return;
    }
    final random = OriginalRandom(doc.text('seed'));
    final angle = mode == 'fusion'
        ? (random.nextDouble() * 360).floor() * math.pi / 180
        : math.pi / 2;
    void gradient(double a, Color first, Color second) {
      final v = Offset(math.cos(a) * r.width / 2, math.sin(a) * r.height / 2);
      c.drawRect(
        r,
        Paint()
          ..shader = ui.Gradient.linear(r.center - v, r.center + v, [
            first,
            second,
          ]),
      );
    }

    gradient(angle, p[0], p[1]);
    gradient(
      mode == 'fusion'
          ? (((angle * 180 / math.pi + 50 + random.nextDouble() * 120) % 360)
                    .floor()) *
                math.pi /
                180
          : 0,
      Color.lerp(p[2], p[0], .35)!.withAlpha(92),
      Color.lerp(p[3], p[1], .35)!.withAlpha(12),
    );
    final sigma = mode == 'sample'
        ? 0.0
        : mode == 'ink'
        ? 30 / scale
        : _sigma(doc.n('blurStrength'), 20, 1.4) *
              math.max(1, scale * .65) /
              scale;
    c.saveLayer(
      r,
      Paint()
        ..imageFilter = (sigma > 0
            ? ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma)
            : null),
    );
    if (mode == 'fusion') {
      final count = 3 + random.nextInt(4);
      for (int i = 0; i < count; i++) {
        final color = p[random.nextInt(p.length)].withAlpha(
          (78 + random.nextDouble() * 54).round(),
        );
        final radius = r.height * (.18 + random.nextDouble() * .36),
            deform = .82 + random.nextDouble() * .36;
        final x = r.width * (.12 + random.nextDouble() * .76),
            y = r.height * (.12 + random.nextDouble() * .76);
        c.drawOval(
          Rect.fromCenter(
            center: Offset(x, y),
            width: radius * deform * 2,
            height: radius * (2 - deform) * 2,
          ),
          Paint()..color = color,
        );
      }
    } else {
      final blobs = [
        [.15, .25, .38],
        [.85, .25, .42],
        [.55, .85, .44],
        [.35, .70, .28],
      ];
      for (int i = 0; i < 4; i++) {
        final b = blobs[i];
        c.drawCircle(
          Offset(r.width * b[0], r.height * b[1]),
          r.height * b[2],
          Paint()..color = p[i].withAlpha(110),
        );
      }
    }
    c.restore();
    c.drawRect(r, Paint()..color = const Color(0x12ffffff));
  }

  Future<Uint8List> _pixels(ui.Image image, int side) async {
    final rec = ui.PictureRecorder(), c = Canvas(rec);
    final w = math.max(
          1,
          (image.width >= image.height
                  ? side
                  : side * image.width / image.height)
              .round(),
        ),
        h = math.max(
          1,
          (image.height >= image.width
                  ? side
                  : side * image.height / image.width)
              .round(),
        );
    c.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final pic = rec.endRecording();
    final small = await pic.toImage(w, h);
    try {
      return (await small.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
    } finally {
      small.dispose();
      pic.dispose();
    }
  }

  ui.Image? _paletteCover;
  String? _paletteKey;
  Future<List<Color>>? _paletteResult;
  Future<List<Color>> _palette(CardDocument doc, ui.Image? cover) {
    final key =
        '${doc.text('paletteAlgorithm')}:${doc.data['customEnvironmentColorsEnabled']}:${doc.data['customEnvironmentColors']}';
    if (identical(cover, _paletteCover) &&
        key == _paletteKey &&
        _paletteResult != null) {
      return _paletteResult!;
    }
    _paletteCover = cover;
    _paletteKey = key;
    final result = _computePalette(CardDocument(deepCopy(doc.data)), cover);
    _paletteResult = result;
    // Keep only one result; failed calculations are allowed to retry.
    result.then(
      (_) {},
      onError: (Object e, StackTrace st) {
        if (identical(_paletteResult, result)) _paletteResult = null;
      },
    );
    return result;
  }

  Future<List<Color>> _computePalette(CardDocument doc, ui.Image? cover) async {
    final custom = doc.data['customEnvironmentColors'];
    if (doc.data['customEnvironmentColorsEnabled'] == true &&
        custom is List &&
        custom.length == 5) {
      return custom.map((x) => tokenColor('$x', Colors.grey)).toList();
    }
    if (cover == null) {
      return [
        const Color(0xffe3c7b8),
        const Color(0xffb6c7de),
        const Color(0xffd9c6db),
        const Color(0xffbdd8c9),
        const Color(0xffe1d2a8),
      ];
    }
    if (doc.text('paletteAlgorithm') != 'histogram') {
      return (await CoverPixels.read(cover, 128)).palette(
        doc.text('paletteAlgorithm').isEmpty
            ? 'celebi'
            : doc.text('paletteAlgorithm'),
      );
    }
    final bytes = await _pixels(cover, 64), bins = <int, List<int>>{};
    for (int i = 0; i < bytes.length; i += 4) {
      if (bytes[i + 3] < 128) continue;
      final key =
          (bytes[i] >> 4) << 8 | (bytes[i + 1] >> 4) << 4 | (bytes[i + 2] >> 4);
      final a = bins.putIfAbsent(key, () => [0, 0, 0, 0]);
      a[0]++;
      a[1] += bytes[i];
      a[2] += bytes[i + 1];
      a[3] += bytes[i + 2];
    }
    final sorted = bins.values.toList()..sort((a, b) => b[0].compareTo(a[0]));
    final result = <Color>[];
    for (final a in sorted) {
      final color = Color.fromARGB(
        255,
        a[1] ~/ a[0],
        a[2] ~/ a[0],
        a[3] ~/ a[0],
      );
      if (result.every(
        (c) =>
            (c.r - color.r).abs() +
                (c.g - color.g).abs() +
                (c.b - color.b).abs() >
            .25,
      )) {
        result.add(color);
      }
      if (result.length == 5) break;
    }
    if (result.isEmpty) result.add(Colors.grey);
    while (result.length < 5) {
      result.add(result[result.length % result.length]);
    }
    return result;
  }

  Future<List<String>> environment(CardDocument doc, ui.Image? cover) async =>
      (await _palette(
        doc,
        cover,
      )).map((c) => '#${c.toARGB32().toRadixString(16).substring(2)}').toList();
  Future<void> benchmarkRainbow(CardDocument doc, ui.Image cover) async {
    final copy = CardDocument(deepCopy(doc.data));
    copy.data['rainbowMode'] = 'auto';
    await _rainbow(copy, cover, const [
      Colors.black,
      Colors.white,
      Colors.grey,
      Colors.red,
      Colors.blue,
    ]);
  }

  ui.Image? _rainbowCover;
  int? _rainbowSide;
  Color? _rainbowColor;
  Future<Color> _rainbow(
    CardDocument doc,
    ui.Image? cover,
    List<Color> palette,
  ) async {
    if (doc.text('rainbowMode') == 'custom') {
      final index = int.tryParse(doc.text('rainbowCustomSelection'));
      if (index != null && index >= 0 && index < 5) return palette[index];
      return tokenColor(
        doc.text('rainbowCustomHex'),
        palette.map(luminance).reduce((a, b) => a + b) / 5 > .5
            ? const Color(0xff121212)
            : const Color(0xfffafafa),
      );
    }
    if (cover == null) return Colors.red;
    final side = doc.n('rainbowSampleMaxSide', 150).toInt().clamp(1, 1000);
    if (identical(cover, _rainbowCover) &&
        side == _rainbowSide &&
        _rainbowColor != null) {
      return _rainbowColor!;
    }
    final bytes = await _pixels(cover, side);
    double sin = 0, cos = 0;
    for (int i = 0; i < bytes.length; i += 4) {
      if (bytes[i + 3] < 128) continue;
      final h = HSVColor.fromColor(
        Color.fromARGB(255, bytes[i], bytes[i + 1], bytes[i + 2]),
      );
      if (h.saturation < .00001) continue;
      sin += math.sin(h.hue * math.pi / 180);
      cos += math.cos(h.hue * math.pi / 180);
    }
    final result = HSVColor.fromAHSV(
      1,
      (math.atan2(sin, cos) * 180 / math.pi + 360) % 360,
      1,
      1,
    ).toColor();
    _rainbowCover = cover;
    _rainbowSide = side;
    _rainbowColor = result;
    return result;
  }
}

/// A single antialiased silhouette with a Gaussian mask has no contour gaps.
/// Local canvas scale also scales sigma, keeping preview and export consistent.
void paintCoverShadow(Canvas canvas, Path path, double depth, double opacity) {
  if (depth <= 0 || opacity <= 0) return;
  canvas.drawPath(
    path,
    Paint()
      ..isAntiAlias = true
      ..color = Colors.black.withValues(alpha: (opacity / 255).clamp(0, 1))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, depth.clamp(0, 100) / 2),
  );
}
