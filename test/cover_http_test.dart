import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/cover_search.dart';

void main() {
  test('HttpClient handles JSON, form posts, bounded streams, errors and cancellation', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final http = CoverHttp();
    final requests = <String>[];
    server.listen((r) async {
      requests.add(r.uri.path);
      if (r.uri.path == '/json') {
        r.response.headers.contentType = ContentType.json;
        r.response.write('{"ok":true}');
      } else if (r.uri.path == '/form') {
        r.response.write(
          jsonEncode({'body': await utf8.decoder.bind(r).join()}),
        );
      } else if (r.uri.path == '/large') {
        r.response.add(List.filled(1024, 1));
      } else if (r.uri.path == '/slow') {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        r.response.write('slow');
      } else {
        r.response.statusCode = 403;
      }
      await r.response.close();
    });
    Uri uri(String p) => Uri.parse('http://127.0.0.1:${server.port}$p');
    try {
      expect(await http.json(uri('/json'), CoverCancel()), {'ok': true});
      final form = await http.json(
        uri('/form'),
        CoverCancel(),
        form: {'q': '晴天 & cover'},
      );
      expect(form['body'], 'q=%E6%99%B4%E5%A4%A9+%26+cover');
      await expectLater(
        http.read(uri('/large'), CoverCancel(), maxBytes: 100),
        throwsFormatException,
      );
      await expectLater(
        http.read(uri('/403'), CoverCancel()),
        throwsA(isA<HttpException>()),
      );
      final cancel = CoverCancel();
      final slow = http.read(uri('/slow'), cancel);
      final check = expectLater(slow, throwsA(anything));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      cancel.cancel();
      await check;
      await expectLater(
        http.read(Uri.parse('http://example.com'), CoverCancel()),
        throwsFormatException,
      );
      expect(requests.where((v) => v == '/403').length, 1);
    } finally {
      http.close();
      await server.close(force: true);
    }
  });
  test('Netease encryption matches independent OpenSSL protocol vectors', () {
    expect(
      NeteaseCipher.eapi({'s': 'Song', 'type': '1'})['params'],
      '2B5D64177AA6460FBAA3DCB1285E28954BBB4F7556E09B0FB25750F12398BB509EA34AFA6B4AEE4F99F76012A4868EF9BA6708BC572F308514FF634FB3C369FB1A36D0D7A4657B78629066042656E7A778347D18040BDB178F1F8E7581554E6318414BBCADEA8EDB9FB39D48C2C9215C',
    );
    final form = NeteaseCipher.weapi({
      's': 'Song',
      'type': '1',
    }, secret: 'abcdefghijklmnop');
    expect(
      form['params'],
      '8Z1j2XX3jzhnIw22Dpsj/7gnhsKbr82keQIzwuhLE5ErSwe9nQy+6JdfIEmqeTri',
    );
    expect(form['encSecKey']!.length, 256);
  });
}
