import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/music_share.dart';
import 'package:musiccardx/cover_search.dart';
import 'package:musiccardx/song_fields.dart';
import 'package:musiccardx/metadata_prompt.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/song_search_page.dart';

String fixture(String name) =>
    File('test/fixtures/share/$name').readAsStringSync();

class ReplayHttp extends ShareHttp {
  @override
  Future<String> text(
    Uri u,
    CoverCancel c, {
    Map<String, dynamic>? post,
    Map<String, String> headers = const {},
  }) async {
    c.check();
    if (u.path.contains('song/detail')) return fixture('netease-song.json');
    if (u.host == 'music.163.com') return fixture('netease-album.json');
    if (u.host == 'c.y.qq.com') return fixture('qq-song.json');
    if (u.host == 'u.y.qq.com') {
      return jsonEncode({
        'album': {
          'data': {
            'totalNum': 11,
            'songList': List.generate(
              11,
              (i) => {
                'songInfo': {'mid': i == 1 ? '00265Jxe3JzXOJ' : 'simulated-$i'},
              },
            ),
          },
        },
      }); // SIMULATED album list; not a recorded QQ POST.
    }
    if (u.host == 'bd-api.kuwo.cn') {
      return fixture(
        u.path.contains('/mv/') ? 'bodian-mv.json' : 'kuwo-song.json',
      );
    }
    if (u.host == 'search.kuwo.cn') return fixture('kuwo-album.txt');
    if (u.host == 'music.douyin.com') return fixture('soda-track.html');
    if (u.host == 'www.qishui.com') return fixture('soda-album.html');
    if (u.host == 'www.kugou.com') return fixture('kugou-www.html');
    if (u.host == 'm.kugou.com') return fixture('kugou.html');
    throw const FormatException('recorded album unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(CardDocument.initialize);
  test(
    'fenced JSON is strict, cover is metadata only, prompt has all nine fields',
    () {
      expect(
        decodeSongJson(
          '```json\n{"title":"爱我别走","cover":"/storage/example.jpg"}\n```',
        )['cover'],
        '/storage/example.jpg',
      );
      expect(
        () => decodeSongJson('explanation\n```json\n{}\n```'),
        throwsFormatException,
      );
      expect(() => decodeSongJson('[1]'), throwsFormatException);
      expect(
        normalizeSongFields({
          'cover': ['invalid'],
          'title': '保留',
        }),
        {'title': '保留'},
      );
      final p = metadataPrompt({'title': '爱我别走', 'album artist': '张震岳'});
      expect(p, contains('"album artist": "张震岳"'));
      expect(p, contains('必须包含全部 9 个字段'));
      expect(p, contains('轻度级别校正（title、artist、album）'));
      expect(
        p,
        contains('重度级别校正（discnumber、totaldiscs、tracknumber、totaltracks）'),
      );
      expect(p, contains('其他已提供字段（如 album artist、date）只允许做不改变语义的规范化'));
      expect(p, contains('9. 已提供字段若被规范化或纠正'));
      expect(p, isNot(contains('{{filled_fields_json}}')));
      expect(p, contains('```json'));
    },
  );
  test(
    'link extraction, hostile hosts, legacy quoting and balanced objects',
    () {
      expect(
        shareLinks(
          '[歌曲](https://music.163.com/song?id=1)，https://m.kuwo.cn/yinyue/2；https://music.163.com/song?id=1',
        ).length,
        2,
      );
      expect(shareLinks('https://y.qq.com.evil.test/song?id=1'), isEmpty);
      expect(ShareHttp.allowed(Uri.parse('http://127.0.0.1/a')), false);
      expect(
        ShareHttp.allowed(Uri.parse('https://user:pass@y.qq.com/a')),
        false,
      );
      expect(
        looseJson("{'name': 'i don\\'t', 'array': [1, 2]}")['name'],
        "i don't",
      );
      expect(
        jsonDecode(
          assignedObject(
            'window._ROUTER_DATA = {"a":{"b":"}"}};',
            '_ROUTER_DATA',
          ),
        )['a']['b'],
        '}',
      );
    },
  );
  test(
    'complete album inference handles multiple discs and refuses partial lists',
    () {
      final rows = [
        {'id': 'a', 'disc': '01'},
        {'id': 'b', 'disc': '02'},
        {'id': 'c', 'disc': '02'},
      ];
      expect(shareAlbum(rows, 'c', 3), {
        'discnumber': '2',
        'totaldiscs': '2',
        'tracknumber': '2',
        'totaltracks': '2',
      });
      expect(shareAlbum(rows, 'c', 8).containsKey('tracknumber'), false);
      expect(
        shareAlbum(
          [
            {'id': 'x'},
          ],
          'x',
          1,
        ).containsKey('discnumber'),
        false,
      );
    },
  );
  test(
    'recorded six-platform response replay, QQ list is explicitly simulated',
    () async {
      final svc = MusicShareService(http: ReplayHttp());
      final c = CoverCancel();
      final net = await svc.one(
        Uri.parse('https://music.163.com/song?id=2091914322'),
        c,
      );
      expect(net.candidate.fields['tracknumber'], '2');
      expect(net.candidate.fields['discnumber'], '1');
      final qq = await svc.one(
        Uri.parse('https://y.qq.com/n/ryqq/songDetail/00265Jxe3JzXOJ'),
        c,
      );
      expect(qq.candidate.fields['tracknumber'], '2');
      expect(qq.candidate.fields['totaltracks'], '11');
      final kw = await svc.one(
        Uri.parse('https://m.kuwo.cn/yinyue/56102277'),
        c,
      );
      expect(kw.candidate.fields['tracknumber'], '8');
      expect(kw.candidate.fields['artist'], '伍佰 & China Blue');
      final kg = await svc.one(
        Uri.parse('https://m.kugou.com/share/song.html?chain=8MSZf5G7V2'),
        c,
      );
      expect(kg.candidate.fields['artist'], '许嵩、黄龄');
      expect(kg.candidate.fields['tracknumber'], isNull);
      final mv = await svc.one(
        Uri.parse('https://h5app.kuwo.cn/m/bodian/play.html?mvId=502980'),
        c,
      );
      expect(mv.cover, contains('wmvpic'));
      expect(mv.candidate.fields['album'], isNull);
      final soda = await svc.one(
        Uri.parse(
          'https://music.douyin.com/qishui/share/track?track_id=7169644136629274663',
        ),
        c,
      );
      expect(soda.candidate.fields['tracknumber'], '3');
      expect(soda.candidate.fields['totaltracks'], '10');
      svc.close();
    },
  );
  test('current Kugou desktop share page preserves song identity', () async {
    final svc = MusicShareService(http: ReplayHttp());
    final r = await svc.one(
      Uri.parse('https://www.kugou.com/share/8MSZf5G7V2.html'),
      CoverCancel(),
    );
    expect(r.candidate.fields['title'], '惊鸿一面');
    expect(r.candidate.fields['artist'], '许嵩、黄龄');
    expect(r.candidate.fields['tracknumber'], isNull);
    svc.close();
  });
  test(
    'cover size fallback keeps source URLs and original request semantics',
    () {
      final urls = shareCoverUrls(
        'https://y.gtimg.cn/music/photo_new/T002R500x500M000test.jpg',
        1000,
      );
      expect(urls.first.toString(), contains('1000x1000'));
      expect(urls[1].toString(), contains('500x500'));
    },
  );
  testWidgets('three tabs, eight optional AI fields and editable prompt', (
    t,
  ) async {
    t.view.physicalSize = const Size(1000, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final d = CardDocument.fresh();
    d.fields['title'] = '用户标题';
    await t.pumpWidget(
      MaterialApp(
        home: SongSearchPage(document: d, onSettings: () async {}),
      ),
    );
    await t.tap(find.text('AI外包'));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(8));
    await t.ensureVisible(find.text('生成提示词'));
    await t.tap(find.text('生成提示词'));
    await t.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget);
    final fields = t.widgetList<TextField>(find.byType(TextField));
    expect(
      fields.any((f) => f.controller?.text.contains('用户标题') ?? false),
      true,
    );
    await t.tap(find.text('来自音乐软件'));
    await t.pumpAndSettle();
    expect(find.text('解析'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
