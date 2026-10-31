// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:musiccardx/cover_search.dart';
import 'package:musiccardx/song_search.dart';

Future<void> main(List<String> args) async {
  final http = CoverHttp();
  // Only this development probe uses the host's optional HTTP proxy.
  http.client.findProxy = HttpClient.findProxyFromEnvironment;
  final client = SongSearchClient(covers: CoverSearchClient(http: http));
  await Future.wait(
    SongSearchClient.sources.keys
        .where((s) => args.isEmpty || args.contains(s))
        .map((source) async {
          final token = CoverCancel();
          try {
            print('$source start');
            final rows = await client
                .searchSource(source, '晴天', '周杰伦', '', 'cn', token)
                .timeout(
                  const Duration(seconds: 40),
                  onTimeout: () {
                    token.cancel();
                    throw const FormatException('源站请求超时');
                  },
                );
            print('$source candidates=${rows.length}');
            if (rows.isNotEmpty) {
              final item = await client.details(rows.first, 'cn', token);
              print('$source ${jsonEncode(item.fields)} ${item.detailError}');
            }
          } catch (e) {
            print('$source ${conciseError(e)}');
          }
        }),
  );
  client.close();
  print('All source checks finished');
}
