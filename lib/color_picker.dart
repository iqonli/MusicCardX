import 'dialog_buttons.dart';

import 'package:flutter/material.dart';

import 'model.dart';
import 'hex_text.dart';

String colorHex(Color c) =>
    '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toLowerCase()}';
Color inverseColor(Color c) => Color(0xff000000 | (~c.toARGB32() & 0xffffff));
Future<String?> pickCardColor(
  BuildContext context,
  String value, {
  bool expression = false,
  String title = '自定义颜色',
}) => showCardDialog<String>(
  context: context,
  builder: (_) =>
      CardColorDialog(value: value, expression: expression, title: title),
);

class CardColorDialog extends StatefulWidget {
  final String value, title;
  final bool expression;
  const CardColorDialog({
    super.key,
    required this.value,
    this.expression = false,
    this.title = '自定义颜色',
  });
  @override
  State<CardColorDialog> createState() => _CardColorDialogState();
}

class _CardColorDialogState extends State<CardColorDialog> {
  late HSVColor hsv;
  late TextEditingController hex;
  late List<TextEditingController> rgb, hsl;
  String? error;
  Color get color => hsv.toColor();
  @override
  void initState() {
    super.initState();
    final s = widget.value.toLowerCase();
    final c = RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(s)
        ? Color(0xff000000 | int.parse(s.replaceAll('#', ''), radix: 16))
        : const Color(0xff2196f3);
    hsv = HSVColor.fromColor(c);
    hex = TextEditingController(
      text:
          !widget.expression &&
              RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(widget.value)
          ? widget.value.replaceAll('#', '').toLowerCase()
          : widget.value.toLowerCase(),
    );
    rgb = List.generate(3, (_) => TextEditingController());
    hsl = List.generate(3, (_) => TextEditingController());
    sync(keepHex: true);
  }

  void sync({bool keepHex = false}) {
    if (!keepHex) hex.text = colorHex(color).substring(1);
    final c = color, h = HSLColor.fromColor(c);
    final a = [(c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round()];
    final b = [
      h.hue.round(),
      (h.saturation * 100).round(),
      (h.lightness * 100).round(),
    ];
    for (int i = 0; i < 3; i++) {
      rgb[i].text = '${a[i]}';
      hsl[i].text = '${b[i]}';
    }
    error = null;
  }

  void channel(bool isRgb) {
    final fields = isRgb ? rgb : hsl;
    final values = fields.map((c) => double.tryParse(c.text)).toList();
    if (values.any((v) => v == null)) return;
    final a = values[0]!, b = values[1]!, c = values[2]!;
    if (a < 0 ||
        b < 0 ||
        c < 0 ||
        a > (isRgb ? 255 : 360) ||
        b > (isRgb ? 255 : 100) ||
        c > (isRgb ? 255 : 100)) {
      return;
    }
    setState(() {
      hsv = HSVColor.fromColor(
        isRgb
            ? Color.fromARGB(255, a.round(), b.round(), c.round())
            : HSLColor.fromAHSL(1, a, b / 100, c / 100).toColor(),
      );
      hex.text = colorHex(color).substring(1);
      final other = isRgb ? hsl : rgb;
      final h = HSLColor.fromColor(color);
      final v = isRgb
          ? [
              h.hue.round(),
              (h.saturation * 100).round(),
              (h.lightness * 100).round(),
            ]
          : [
              (color.r * 255).round(),
              (color.g * 255).round(),
              (color.b * 255).round(),
            ];
      for (int i = 0; i < 3; i++) {
        other[i].text = '${v[i]}';
      }
    });
  }

  @override
  void dispose() {
    hex.dispose();
    for (final c in [...rgb, ...hsl]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, box) => GestureDetector(
                onPanDown: (d) => sv(d.localPosition, box.maxWidth),
                onPanUpdate: (d) => sv(d.localPosition, box.maxWidth),
                child: SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white,
                                HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (hsv.saturation * box.maxWidth - 7).clamp(
                          0,
                          box.maxWidth - 14,
                        ),
                        top: ((1 - hsv.value) * 180 - 7).clamp(0, 166),
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [BoxShadow(blurRadius: 2)],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, box) => GestureDetector(
                onPanDown: (d) => hue(d.localPosition.dx / box.maxWidth),
                onPanUpdate: (d) => hue(d.localPosition.dx / box.maxWidth),
                child: SizedBox(
                  height: 28,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 10,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: LinearGradient(
                            colors: List.generate(
                              7,
                              (i) =>
                                  HSVColor.fromAHSV(1, i * 60, 1, 1).toColor(),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (hsv.hue / 360 * box.maxWidth - 9).clamp(
                          0,
                          box.maxWidth - 18,
                        ),
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 38,
              width: double.infinity,
              color: color,
              alignment: Alignment.center,
              child: Text(
                colorHex(color),
                style: TextStyle(color: inverseColor(color)),
              ),
            ),
            for (final isRgb in [true, false])
              Row(
                children: [
                  for (int i = 0; i < 3; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                        child: TextField(
                          controller: (isRgb ? rgb : hsl)[i],
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: (isRgb
                                ? ['R', 'G', 'B']
                                : ['H', 'S', 'L'])[i],
                            border: const UnderlineInputBorder(),
                          ),
                          onChanged: (_) => channel(isRgb),
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            TextField(
              controller: hex,
              inputFormatters: const [LowerHexFormatter()],
              decoration: InputDecoration(
                labelText: widget.expression ? 'HEX / 颜色表达式' : 'HEX',
                prefixText: widget.expression ? null : '# ',
                border: const UnderlineInputBorder(),
                errorText: error,
              ),
              onChanged: (s) {
                final n = int.tryParse(s.replaceAll('#', ''), radix: 16);
                if (n != null && s.replaceAll('#', '').length == 6) {
                  setState(() {
                    hsv = HSVColor.fromColor(Color(0xff000000 | n));
                    sync(keepHex: true);
                  });
                }
              },
            ),
            if (widget.expression)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    setState(() => hex.text = '');
                  },
                  child: const Text('自动黑白色'),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () {
          final s = hex.text.trim();
          if (widget.expression
              ? validColor(s)
              : RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(s)) {
            Navigator.pop(
              context,
              RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(s)
                  ? '#${s.replaceAll('#', '').toLowerCase()}'
                  : s,
            );
          } else {
            setState(() => error = '颜色格式无效');
          }
        },
        child: const Text('确定'),
      ),
    ],
  );
  void sv(Offset p, double width) {
    setState(() {
      hsv = hsv
          .withSaturation((p.dx / width).clamp(0, 1))
          .withValue((1 - p.dy / 180).clamp(0, 1));
      sync();
    });
  }

  void hue(double v) {
    setState(() {
      hsv = hsv.withHue(v.clamp(0, 1) * 360);
      sync();
    });
  }
}
