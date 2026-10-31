// ignore_for_file: avoid_print
import 'package:musiccardx/cover_search.dart';

Future<void> main() async {
  final client = CoverSearchClient();
  await Future.wait(
    CoverSearchClient.sources.keys.map((s) async {
      final cancel = CoverCancel();
      try {
        final rows = await client.searchSource(s, '晴天 周杰伦', 'cn', cancel);
        print('$s candidates=${rows.length}');
        if (rows.isNotEmpty) {
          final b = await client.artwork(rows.first, 150, cancel);
          print('$s thumbnailBytes=${b.length} signature=${imageSignature(b)}');
        }
      } catch (e) {
        print('$s ${conciseError(e)}');
      }
    }),
  );
  client.close();
}
