// ignore_for_file: avoid_print
import 'package:musiccardx/cover_search.dart';
import 'package:image/image.dart' as img;

Future<void> main() async {
  final c = CoverSearchClient();
  for (final source in ['apple', 'appleweb']) {
    final token = CoverCancel();
    try {
      final rows = await c.searchSource(
        source,
        source == 'apple' ? 'Taylor Swift' : '晴天 周杰伦',
        source == 'apple' ? 'us' : 'cn',
        token,
      );
      print('$source candidates=${rows.length}');
      for (final size in [150, 1000]) {
        if (rows.isEmpty) break;
        final b = await c.artwork(rows.first, size, token);
        final decoded = img.decodeImage(b);
        print(
          '$source requested=$size actual=${decoded?.width}x${decoded?.height} bytes=${b.length}',
        );
      }
    } catch (e) {
      print('$source ${conciseError(e)}');
    }
  }
  c.close();
}
