import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class ImageExportOptions {
  final String format;
  final int quality;
  const ImageExportOptions({this.format = 'png', this.quality = 95});
  factory ImageExportOptions.fromMap(Map<String, dynamic> map) {
    final q = map['jpegQuality'];
    return ImageExportOptions(
      format: map['imageFormat'] == 'jpg' ? 'jpg' : 'png',
      quality: (q is num && q.isFinite ? q.round() : 95).clamp(1, 100),
    );
  }
  String get mimeType => format == 'jpg' ? 'image/jpeg' : 'image/png';
  String get label => format == 'jpg' ? 'JPG 质量$quality' : 'PNG';
  Map<String, dynamic> toMap() => {
    'imageFormat': format,
    'jpegQuality': quality,
  };
}

class EncodedExport {
  final Uint8List bytes;
  final ImageExportOptions options;
  const EncodedExport(this.bytes, this.options);
  String get extension => options.format;
  String get mimeType => options.mimeType;
}

class _JpegWork {
  final int width, height, quality;
  final TransferableTypedData pixels;
  const _JpegWork(this.width, this.height, this.quality, this.pixels);
}

Uint8List _jpeg(_JpegWork work) {
  final raw = work.pixels.materialize().asUint8List();
  // JPEG has no alpha. Composite straight RGBA onto white while creating RGB,
  // so no PNG intermediate or second full-size matte image is needed.
  final image = img.Image(
    width: work.width,
    height: work.height,
    numChannels: 3,
  );
  final rgb = image.data!.getBytes();
  for (
    int source = 0, target = 0;
    source < raw.length;
    source += 4, target += 3
  ) {
    final alpha = raw[source + 3];
    for (int c = 0; c < 3; c++) {
      rgb[target + c] =
          (raw[source + c] * alpha + 255 * (255 - alpha) + 127) ~/ 255;
    }
  }
  return img.encodeJpg(
    image,
    quality: work.quality,
    chroma: img.JpegChroma.yuv444,
  );
}

Future<EncodedExport> encodeExportImage(
  ui.Image image,
  ImageExportOptions options,
) async {
  if (options.format == 'png') {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return EncodedExport(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      options,
    );
  }
  final raw = (await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  ))!;
  final pixels = TransferableTypedData.fromList([
    raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
  ]);
  final encoded = await compute(
    _jpeg,
    _JpegWork(image.width, image.height, options.quality, pixels),
  );
  return EncodedExport(encoded, options);
}

class ImageCompressionDialog extends StatefulWidget {
  final ImageExportOptions initial;
  const ImageCompressionDialog({super.key, required this.initial});
  @override
  State<ImageCompressionDialog> createState() => _ImageCompressionDialogState();
}

class _ImageCompressionDialogState extends State<ImageCompressionDialog> {
  late String format = widget.initial.format;
  late int quality = widget.initial.quality;
  late final controller = TextEditingController(text: '$quality');
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('图片压缩'),
    content: SizedBox(
      width: 360,
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'png', label: Text('PNG')),
                ButtonSegment(value: 'jpg', label: Text('JPG')),
              ],
              selected: {format},
              onSelectionChanged: (values) =>
                  setState(() => format = values.single),
            ),
            if (format == 'jpg') ...[
              const SizedBox(height: 20),
              TextFormField(
                key: const ValueKey('jpeg-quality'),
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '质量',
                  suffixText: '%',
                ),
                onTap: () => controller.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: controller.text.length,
                ),
                validator: (s) {
                  final n = int.tryParse(s ?? '');
                  return n == null || n < 1 || n > 100 ? '请输入1到100' : null;
                },
                onChanged: (s) {
                  final n = int.tryParse(s);
                  if (n != null && n >= 1 && n <= 100) {
                    setState(() => quality = n);
                  }
                },
              ),
              Slider(
                value: quality.toDouble(),
                min: 1,
                max: 100,
                divisions: 99,
                label: '$quality',
                onChanged: (v) => setState(() {
                  quality = v.round();
                  controller.text = '$quality';
                }),
              ),
            ],
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
          if (format == 'png' || form.currentState!.validate()) {
            Navigator.pop(
              context,
              ImageExportOptions(format: format, quality: quality),
            );
          }
        },
        child: const Text('确定'),
      ),
    ],
  );
}
