// ignore_for_file: avoid_print
import 'package:musiccardx/cover_search.dart';

Future<void> main() async {
  final c = CoverSearchClient();
  for (final source in ['appleweb', 'apple']) {
    final cancel = CoverCancel();
    try {
      final rows = await c.searchSource(
        source,
        source == 'appleweb' ? '晴天 周杰伦' : 'Taylor Swift',
        'us',
        cancel,
      );
      print('$source ${rows.length}');
      if (rows.isNotEmpty) {
        print(rows.first.artwork);
        for (final u in CoverSearchClient.artworkUrls(
          rows.first.artwork,
          150,
          apple: true,
        ).take(3)) {
          print(u);
        }
      }
    } catch (e) {
      print(conciseError(e));
    }
  }
  c.close();
}
