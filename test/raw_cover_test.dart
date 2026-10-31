import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/raw_cover.dart';

void main() {
  test('raw covers preserve source bytes and file formats', () async {
    final root = await Directory.systemTemp.createTemp('mcx-raw-');
    try {
      for (final pair in [
        ([255, 216, 255, 1, 2, 3], 'jpg'),
        ([137, 80, 78, 71, 13, 10, 26, 10, 1, 2], 'png'),
        ([71, 73, 70, 56, 57, 97, 1], 'gif'),
        ([82, 73, 70, 70, 1, 2, 3, 4, 87, 69, 66, 80], 'webp'),
      ]) {
        final bytes = Uint8List.fromList(pair.$1);
        final type = coverFileType(bytes);
        expect(type.extension, pair.$2);
        final file = await writeRawCover(
          root,
          'test-cover.${type.extension}',
          bytes,
        );
        expect(await file.readAsBytes(), bytes);
        final duplicate = await writeRawCover(
          root,
          'test-cover.${type.extension}',
          bytes,
        );
        expect(duplicate.path, isNot(file.path));
        expect(await duplicate.readAsBytes(), bytes);
      }
      expect(
        () => coverFileType(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}
