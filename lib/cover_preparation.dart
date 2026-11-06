import 'dart:typed_data';
import 'package:image/image.dart' as im;
im.Image boxBlur(im.Image image, int radius) {
  final w = image.width, h = image.height;
  final src = Float64List(w * h * 3),
      tmp = Float64List(w * h * 3),
      out = im.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = image.getPixel(x, y), i = (y * w + x) * 3;
      src[i] = p.r.toDouble();
      src[i + 1] = p.g.toDouble();
      src[i + 2] = p.b.toDouble();
    }
  }
  for (var y = 0; y < h; y++) {
    for (var c = 0; c < 3; c++) {
      double sum = 0;
      for (var k = -radius; k <= radius; k++) {
        sum += src[(y * w + k.clamp(0, w - 1)) * 3 + c];
      }
      for (var x = 0; x < w; x++) {
        tmp[(y * w + x) * 3 + c] = sum / (radius * 2 + 1);
        sum +=
            src[(y * w + (x + radius + 1).clamp(0, w - 1)) * 3 + c] -
            src[(y * w + (x - radius).clamp(0, w - 1)) * 3 + c];
      }
    }
  }
  final values = Float64List(w * h * 3);
  for (var x = 0; x < w; x++) {
    for (var c = 0; c < 3; c++) {
      double sum = 0;
      for (var k = -radius; k <= radius; k++) {
        sum += tmp[(k.clamp(0, h - 1) * w + x) * 3 + c];
      }
      for (var y = 0; y < h; y++) {
        values[(y * w + x) * 3 + c] = sum / (radius * 2 + 1);
        sum +=
            tmp[((y + radius + 1).clamp(0, h - 1) * w + x) * 3 + c] -
            tmp[((y - radius).clamp(0, h - 1) * w + x) * 3 + c];
      }
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      out.setPixelRgb(
        x,
        y,
        values[i].round(),
        values[i + 1].round(),
        values[i + 2].round(),
      );
    }
  }
  return out;
}

Map<String, Object> prepareMistCover(Map<String, Object?> args) {
  late im.Image cover;
  if (args['cover'] != null) {
    cover = im.Image.fromBytes(
      width: args['coverWidth'] as int,
      height: args['coverHeight'] as int,
      bytes: (args['cover'] as Uint8List).buffer,
      numChannels: 4,
    );
    cover = im.copyResize(
      cover,
      width: cover.width >= cover.height ? 512 : null,
      height: cover.height > cover.width ? 512 : null,
      interpolation: im.Interpolation.cubic,
    );
  }

  return {
    'width': cover.width,
    'height': cover.height,
    'blur1': boxBlur(cover, 7).getBytes(order: im.ChannelOrder.rgba),
    'blur2': boxBlur(cover, 20).getBytes(order: im.ChannelOrder.rgba),
  };
}
