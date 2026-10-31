import 'dart:io';
import 'dart:typed_data';

({String extension, String mime}) coverFileType(Uint8List b) {
  bool at(int start, List<int> v) =>
      b.length >= start + v.length &&
      List.generate(v.length, (i) => b[start + i] == v[i]).every((x) => x);
  if (at(0, [255, 216, 255])) return (extension: 'jpg', mime: 'image/jpeg');
  if (at(0, [137, 80, 78, 71, 13, 10, 26, 10])) {
    return (extension: 'png', mime: 'image/png');
  }
  if (at(0, [71, 73, 70, 56])) return (extension: 'gif', mime: 'image/gif');
  if (at(0, [82, 73, 70, 70]) && at(8, [87, 69, 66, 80])) {
    return (extension: 'webp', mime: 'image/webp');
  }
  if (at(0, [66, 77])) return (extension: 'bmp', mime: 'image/bmp');
  if (at(0, [73, 73, 42, 0]) || at(0, [77, 77, 0, 42])) {
    return (extension: 'tif', mime: 'image/tiff');
  }
  if (at(4, [102, 116, 121, 112])) {
    final brand = String.fromCharCodes(b.skip(8).take(4));
    if (['avif', 'avis'].contains(brand)) {
      return (extension: 'avif', mime: 'image/avif');
    }
    if (['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'].contains(brand)) {
      return (extension: 'heic', mime: 'image/heic');
    }
  }
  throw const FormatException('无法识别封面图片格式');
}

Future<File> writeRawCover(
  Directory directory,
  String name,
  Uint8List bytes,
) async {
  await directory.create(recursive: true);
  var file = File('${directory.path}/$name');
  if (await file.exists()) {
    final dot = name.lastIndexOf('.');
    file = File(
      '${directory.path}/${name.substring(0, dot)}-${DateTime.now().microsecondsSinceEpoch}${name.substring(dot)}',
    );
  }
  final temporary = File('${file.path}.part');
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    return await temporary.rename(file.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
