import 'dialog_buttons.dart';

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'color_picker.dart';

const paletteAlgorithms = {
  'celebi': 'Celebi',
  'wu': 'Wu',
  'histogram': 'RGB分桶',
  'foobar': '类foobar',
};

class CoverPixels {
  final int width, height;
  final Uint8List bytes;
  CoverPixels(this.width, this.height, this.bytes);
  static Future<CoverPixels> read(ui.Image image, int side) async {
    final ratio = side / math.max(image.width, image.height);
    final w = math.max(1, (image.width * ratio).round()),
        h = math.max(1, (image.height * ratio).round());
    final rec = ui.PictureRecorder();
    Canvas(rec).drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final pic = rec.endRecording();
    final small = await pic.toImage(w, h);
    final data = (await small.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    small.dispose();
    pic.dispose();
    return CoverPixels(w, h, data);
  }

  List<int> get argb => [
    for (int i = 0; i < bytes.length; i += 4)
      if (bytes[i + 3] >= 128)
        0xff000000 | bytes[i] << 16 | bytes[i + 1] << 8 | bytes[i + 2],
  ];
  Color at(int x, int y) {
    final p = ((y.clamp(0, height - 1)) * width + x.clamp(0, width - 1)) * 4;
    return Color.fromARGB(bytes[p + 3], bytes[p], bytes[p + 1], bytes[p + 2]);
  }

  Color average(Offset point, int side, {bool flood = false}) {
    final x = (point.dx * (width - 1)).round(),
        y = (point.dy * (height - 1)).round();
    final radius = side ~/ 2, after = (side - 1) ~/ 2;
    double r = 0, g = 0, b = 0, n = 0;
    for (
      int yy = math.max(0, y - radius);
      yy <= math.min(height - 1, y + after);
      yy++
    ) {
      for (
        int xx = math.max(0, x - radius);
        xx <= math.min(width - 1, x + after);
        xx++
      ) {
        final c = at(xx, yy);
        if (c.a < .5) continue;
        r += c.r;
        g += c.g;
        b += c.b;
        n++;
      }
    }
    if (n == 0) return at(x, y);
    final local = Color.from(alpha: 1, red: r / n, green: g / n, blue: b / n);
    if (!flood) return local;
    // Fixed-seed color distance prevents a flood drifting across an entire gradient.
    final visited = Uint8List(width * height), queue = <int>[y * width + x];
    visited[queue.first] = 1;
    r = 0;
    g = 0;
    b = 0;
    n = 0;
    for (int i = 0; i < queue.length; i++) {
      final p = queue[i], xx = p % width, yy = p ~/ width, c = at(xx, yy);
      r += c.r;
      g += c.g;
      b += c.b;
      n++;
      for (final q in [
        if (xx > 0) p - 1,
        if (xx < width - 1) p + 1,
        if (yy > 0) p - width,
        if (yy < height - 1) p + width,
      ]) {
        if (visited[q] != 0) continue;
        visited[q] = 1;
        final c = at(q % width, q ~/ width);
        final distance =
            math.pow(c.r - local.r, 2) +
            math.pow(c.g - local.g, 2) +
            math.pow(c.b - local.b, 2);
        if (c.a >= .5 && distance < .045) queue.add(q);
      }
    }
    return Color.lerp(
      local,
      Color.from(alpha: 1, red: r / n, green: g / n, blue: b / n),
      .5,
    )!;
  }

  Offset representative(Color color) {
    double best = double.infinity;
    int index = 0;
    for (int i = 0; i < bytes.length; i += 4) {
      if (bytes[i + 3] < 128) continue;
      final d =
          math.pow(bytes[i] - color.r * 255, 2) +
          math.pow(bytes[i + 1] - color.g * 255, 2) +
          math.pow(bytes[i + 2] - color.b * 255, 2);
      if (d < best) {
        best = d.toDouble();
        index = i ~/ 4;
      }
    }
    return Offset(
      index % width / math.max(1, width - 1),
      index ~/ width / math.max(1, height - 1),
    );
  }

  Future<List<Color>> palette(String algorithm, {int count = 5}) async {
    Map<int, int> bins = {};
    if (algorithm == 'celebi' || algorithm == 'foobar') {
      bins = (await QuantizerCelebi().quantize(argb, 32)).colorToCount;
    } else if (algorithm == 'wu') {
      bins = (await QuantizerWu().quantize(argb, 32)).colorToCount;
    } else {
      final hist = <int, List<int>>{};
      for (final p in argb) {
        final r = (p >> 16) & 255, g = (p >> 8) & 255, b = p & 255;
        final k = (r >> 4) << 8 | (g >> 4) << 4 | b >> 4;
        final a = hist.putIfAbsent(k, () => [0, 0, 0, 0]);
        a[0]++;
        a[1] += r;
        a[2] += g;
        a[3] += b;
      }
      bins = {
        for (final a in hist.values)
          0xff000000 |
                  (a[1] ~/ a[0]) << 16 |
                  (a[2] ~/ a[0]) << 8 |
                  a[3] ~/ a[0]:
              a[0],
      };
    }
    // Foobar-like accent selection: cluster first, then favour chromatic,
    // usable midtones without letting a tiny bright speck dominate the cover.
    // This is our implementation of that style, not foobar2000's binary code.
    double vividScore(MapEntry<int, int> e) {
      final h = Hct.fromInt(e.key);
      final population = e.value / math.max(1, width * height);
      final chroma = (h.chroma / 80).clamp(0.0, 1.0);
      final tone = (1 - (h.tone - 55).abs() / 55).clamp(0.0, 1.0);
      return math.sqrt(population) *
          (.08 + chroma * chroma * 2) *
          (.2 + .8 * tone);
    }

    final sorted = bins.entries.toList()
      ..sort((a, b) {
        final c = algorithm == 'foobar'
            ? vividScore(b).compareTo(vividScore(a))
            : b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    final result = <Color>[];
    for (final e in sorted) {
      final c = Color(e.key);
      if (result.every(
        (a) => (a.r - c.r).abs() + (a.g - c.g).abs() + (a.b - c.b).abs() > .25,
      )) {
        result.add(c);
      }
      if (result.length == count) break;
    }
    if (result.isEmpty) result.add(Colors.grey);
    while (result.length < count) {
      result.add(result.first);
    }
    return result;
  }
}

class PalettePointPage extends StatefulWidget {
  final ui.Image image;
  final List<String> initial;
  final String algorithm;
  const PalettePointPage({
    super.key,
    required this.image,
    required this.initial,
    required this.algorithm,
  });
  @override
  State<PalettePointPage> createState() => _PalettePointState();
}

const paletteMarkerDiameter = 25.5 * .7;
const paletteTouchDiameter = paletteMarkerDiameter * 2;

class _PalettePointState extends State<PalettePointPage> {
  CoverPixels? pixels;
  List<Color> colors = [];
  List<Offset> points = [];
  List<int> chosen = [];
  bool flood = false, continuous = false;
  int side = 3;
  String? error;
  final transform = TransformationController();
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final p = await CoverPixels.read(widget.image, 512);
      final c = await p.palette(widget.algorithm, count: 10);
      if (!mounted) return;
      setState(() {
        pixels = p;
        colors = c;
        points = [];
        for (int i = 0; i < c.length; i++) {
          var point = p.representative(c[i]);
          if (points.any((a) => (a - point).distance < .04)) {
            point = Offset(.15 + (i % 5) * .17, .35 + (i ~/ 5) * .3);
          }
          points.add(point);
          c[i] = p.average(point, side);
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  void update(int i, Offset p) {
    final pos = Offset(p.dx.clamp(0, 1), p.dy.clamp(0, 1));
    setState(() {
      points[i] = pos;
      colors[i] = pixels!.average(pos, side, flood: flood);
    });
  }

  Future<void> sizeDialog() async {
    final c = TextEditingController(text: '$side');
    final v = await showCardDialog<int>(
      context: context,
      builder: (cxt) => AlertDialog(
        title: const Text('取色边长'),
        content: TextField(controller: c, keyboardType: TextInputType.number),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(cxt, int.tryParse(c.text)),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (v != null && v >= 1 && v <= 101) {
      setState(() => side = v);
      for (int i = 0; i < points.length; i++) {
        update(i, points[i]);
      }
    }
  }

  Widget canvas() => LayoutBuilder(
    builder: (context, box) {
      final ratio = widget.image.width / widget.image.height;
      final w = math.min(box.maxWidth, box.maxHeight * ratio), h = w / ratio;
      return Center(
        child: InteractiveViewer(
          transformationController: transform,
          minScale: 1,
          maxScale: 8,
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: RawImage(
                    image: widget.image,
                    filterQuality: FilterQuality.high,
                    fit: BoxFit.fill,
                  ),
                ),
                for (int i = 0; i < points.length; i++)
                  Positioned(
                    left: points[i].dx * w - paletteTouchDiameter / 2,
                    top: points[i].dy * h - paletteTouchDiameter / 2,
                    child: GestureDetector(
                      behavior: HitTestBehavior.deferToChild,
                      onTap: () => setState(() {
                        if (!continuous) return;
                        if (chosen.contains(i)) {
                          chosen.remove(i);
                        } else if (chosen.length < 5) {
                          chosen.add(i);
                        }
                      }),
                      onPanUpdate: (d) => update(
                        i,
                        points[i] + Offset(d.delta.dx / w, d.delta.dy / h),
                      ),
                      child: SizedBox(
                        width: paletteTouchDiameter,
                        height: paletteTouchDiameter,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            // The outer circle is a 70%-opacity stroke; its interior remains transparent.
                            Container(
                              width: paletteTouchDiameter,
                              height: paletteTouchDiameter,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colors[i].withValues(alpha: .7),
                                  width: 1,
                                ),
                              ),
                            ),
                            Container(
                              width: paletteMarkerDiameter,
                              height: paletteMarkerDiameter,
                              decoration: BoxDecoration(
                                color: colors[i],
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: chosen.contains(i)
                                      ? Colors.amber
                                      : Colors.white,
                                  width: 1.575,
                                ),
                              ),
                            ),
                            if (chosen.contains(i))
                              IgnorePointer(
                                child: Text(
                                  '${chosen.indexOf(i) + 1}',
                                  style: TextStyle(
                                    color: inverseColor(colors[i]),
                                    fontSize: 12,
                                    height: 1,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(continuous ? '连续选取${chosen.length}/5' : '封面选点'),
      actions: [
        TextButton(
          onPressed: colors.isEmpty
              ? null
              : () => setState(() {
                  continuous = true;
                  chosen = [];
                }),
          child: Text(chosen.length == 5 ? '重新连续选取5个' : '开始连续选取5个'),
        ),
        if (chosen.length == 5)
          IconButton(
            tooltip: '确定',
            onPressed: () => Navigator.pop(context, [
              for (final i in chosen) colorHex(colors[i]),
            ]),
            icon: const Icon(Icons.check),
          ),
      ],
    ),
    body: error != null
        ? Center(child: Text(error!))
        : pixels == null
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Expanded(child: canvas()),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    TextButton(
                      onPressed: sizeDialog,
                      child: Text('取色边长 $side'),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => flood = !flood);
                        for (int i = 0; i < points.length; i++) {
                          update(i, points[i]);
                        }
                      },
                      child: Text('油漆桶模式 ${flood ? '开' : '关'}'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
  );
}
