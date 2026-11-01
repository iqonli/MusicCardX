// ignore_for_file: avoid_print
import 'dart:io';

import 'package:musiccardx/music_share.dart';
import 'package:musiccardx/cover_search.dart';

Future<void> main(List<String> args) async {
  final http = ShareHttp();
  http.client.findProxy = HttpClient.findProxyFromEnvironment;
  final service = MusicShareService(http: http);
  final cases = [
    'https://music.163.com/song?id=2091914322',
    'https://y.qq.com/n/ryqq/songDetail/00265Jxe3JzXOJ',
    'https://m.kugou.com/share/song.html?chain=8MSZf5G7V2',
    'https://m.kuwo.cn/yinyue/56102277',
    'https://h5app.kuwo.cn/m/bodian/play.html?mvId=502980',
    'https://music.douyin.com/qishui/share/track?track_id=7169644136629274663',
  ];
  await Future.wait(
    (args.isEmpty ? cases : args).map((url) async {
      final c = CoverCancel();
      try {
        final r = await service
            .one(Uri.parse(url), c)
            .timeout(const Duration(seconds: 75));
        print('${r.platform} ${r.candidate.fields} ${r.warnings}');
      } catch (e) {
        c.cancel();
        print('${sharePlatform(Uri.parse(url))} ${conciseError(e)}');
      }
    }),
  );
  service.close();
}
