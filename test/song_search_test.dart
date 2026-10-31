import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/cover_search.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/song_search.dart';
import 'package:musiccardx/song_search_page.dart';

const song = CoverCandidate(
  source: 'qq',
  displaySource: 'QQ音乐',
  id: 'mid',
  title: '新标题',
  artist: '新艺术家',
  album: '新专辑',
  artwork: '',
  score: 98,
);
const result = SongCandidate(song, {
  'title': '新标题',
  'artist': '新艺术家',
  'album': '新专辑',
  'date': '2003-07-31',
  'tracknumber': '3',
});

class FakeSongSearch extends SongSearchClient {
  int searches = 0;
  bool fail163 = false;
  @override
  Future<List<CoverCandidate>> searchSource(
    String source,
    String title,
    String artist,
    String album,
    String region,
    CoverCancel cancel,
  ) async {
    searches++;
    if (source == '163' && fail163) throw const FormatException('offline');
    return [song];
  }

  @override
  Future<SongCandidate> details(
    CoverCandidate song,
    String region,
    CoverCancel cancel,
  ) async {
    cancel.check();
    return result;
  }
}

class FakeHttp extends CoverHttp {
  final seen = <Uri>[];
  @override
  Future<Map<String, dynamic>> json(
    Uri uri,
    CoverCancel cancel, {
    Map<String, String> headers = const {},
    Map<String, String>? form,
  }) async {
    cancel.check();
    seen.add(uri);
    if (uri.host == 'c.y.qq.com') {
      return {
        'code': 0,
        'data': {
          'song': {
            'list': [
              {
                'songmid': 'mid',
                'songname': '标题',
                'albumname': '专辑',
                'singer': [
                  {'name': '艺术家'},
                ],
              },
            ],
          },
        },
      };
    }
    return {
      'code': 0,
      'req_0': {
        'code': 0,
        'data': {
          'track_info': {
            'mid': 'mid',
            'name': '标题',
            'index_cd': 0,
            'index_album': 3,
            'time_public': '2003-07-31',
          },
        },
      },
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(CardDocument.initialize);
  test('Apple preserves full date, disc and track totals through scoring', () {
    final c = CoverSearchClient.parse('apple', {
      'results': [
        {
          'wrapperType': 'track',
          'kind': 'song',
          'trackId': 1,
          'trackName': 'Song',
          'artistName': 'Singer',
          'collectionName': 'Album',
          'artworkUrl100':
              'https://is1-ssl.mzstatic.com/image/thumb/Music/a/100x100bb.jpg',
          'releaseDate': '2001-07-05T12:00:00Z',
          'discNumber': 2,
          'discCount': 3,
          'trackNumber': 12,
          'trackCount': 24,
        },
      ],
    }).single.scored(90);
    expect(c.metadata, {
      'date': '2001-07-05',
      'discnumber': '2',
      'totaldiscs': '3',
      'tracknumber': '12',
      'totaltracks': '24',
    });
  });
  test('metadata accepts Apple songs without artwork and album lookup uses exact ID', () {
    final row = {
      'results': [
        {
          'wrapperType': 'track',
          'kind': 'song',
          'trackId': 1,
          'trackName': 'Song',
          'releaseDate': '2001-07-05T12:00:00Z',
        },
      ],
    };
    expect(CoverSearchClient.parse('apple', row), isEmpty);
    expect(
      CoverSearchClient.parse(
        'apple',
        row,
        requireArtwork: false,
      ).single.metadata['date'],
      '2001-07-05',
    );
    final fields = SongSearchClient.appleAlbum({
      'data': [
        {
          'attributes': {'trackCount': 11, 'releaseDate': '2003-07-31'},
          'relationships': {
            'tracks': {
              'data': [
                {
                  'id': 'other',
                  'attributes': {'trackNumber': 7},
                },
                {
                  'id': 'right',
                  'attributes': {'trackNumber': 3, 'discNumber': 1},
                },
              ],
            },
          },
        },
      ],
    }, 'right');
    expect(fields, {
      'date': '2003-07-31',
      'discnumber': '1',
      'tracknumber': '3',
      'totaltracks': '11',
    });
  });
  test('QQ mobile result and detail use real date and zero-based disc', () {
    final list = SongSearchClient.parseQQLegacy({
      'code': 0,
      'data': {
        'song': {
          'list': [
            {
              'songmid': '0039MnYb0qxYhV',
              'songname': '晴天',
              'albumname': '叶惠美',
              'albummid': 'al',
              'pubtime': 1059580800,
              'singer': [
                {'name': '周杰伦'},
              ],
            },
          ],
        },
      },
    });
    expect(list.single.metadata['date'], '2003-07-31');
    final detail = SongSearchClient.qqSong({
      'mid': 'mid',
      'name': '晴天',
      'index_cd': 0,
      'index_album': 3,
      'time_public': '2003-07-31',
    });
    expect(detail.metadata['discnumber'], '1');
    expect(detail.metadata['tracknumber'], '3');
    expect(detail.metadata.containsKey('totaldiscs'), false);
    expect(
      () => SongSearchClient.parseQQLegacy({'code': 500}),
      throwsFormatException,
    );
  });
  test(
    '163 album matches exact ID and does not invent track from list order',
    () {
      final root = {
        'code': 200,
        'album': {'publishTime': 1059580800000, 'size': 11},
        'songs': [
          {'id': 1, 'no': 9},
          {'id': 2, 'no': 3},
        ],
      };
      expect(SongSearchClient.neteaseAlbum(root, '2'), {
        'date': '2003-07-31',
        'tracknumber': '3',
        'totaltracks': '11',
      });
      expect(
        SongSearchClient.neteaseAlbum(
          root,
          'missing',
        ).containsKey('tracknumber'),
        false,
      );
    },
  );
  test(
    'apply only supplied values; keep extra tags and unavailable totals',
    () {
      final fields = applySongCandidate({
        'title': '旧标题',
        'genre': 'Pop',
        'totaltracks': '11',
      }, result);
      expect(fields['title'], '新标题');
      expect(fields['genre'], 'Pop');
      expect(fields['totaltracks'], '11');
      expect(fields.containsKey('totaldiscs'), false);
    },
  );
  test(
    'metadata client uses mobile search and details, never image downloads',
    () async {
      final http = FakeHttp();
      final client = SongSearchClient(covers: CoverSearchClient(http: http));
      final found = await client.searchSource(
        'qq',
        '标题',
        '艺术家',
        '',
        'cn',
        CoverCancel(),
      );
      final item = await client.details(found.single, 'cn', CoverCancel());
      expect(item.fields['tracknumber'], '3');
      expect(item.fields['discnumber'], '1');
      expect(http.seen.length, 2);
      expect(http.seen.first.queryParameters['w'], '标题 艺术家');
      final cancelled = CoverCancel()..cancel();
      await expectLater(
        client.details(found.single, 'cn', cancelled),
        throwsA(isA<CoverCancelled>()),
      );
      client.close();
    },
  );
  test('search settings survive configuration normalization', () {
    final d = CardDocument.fromJson({
      ...CardDocument.fresh().data,
      'songSearch_qq': false,
      'songSearchRegion': 'us',
    });
    expect(d.data['songSearch_qq'], false);
    expect(d.data['songSearchRegion'], 'us');
  });
  testWidgets(
    'title and artist required; partial provider failure retains candidates and bold comparisons',
    (t) async {
      final d = CardDocument.fresh();
      d.data['songSearch_apple'] = false;
      d.fields['title'] = '';
      d.fields['artist'] = '';
      final client = FakeSongSearch()..fail163 = true;
      await t.pumpWidget(
        MaterialApp(
          home: SongSearchPage(
            document: d,
            onSettings: () async {},
            client: client,
          ),
        ),
      );
      await t.tap(find.widgetWithText(TextButton, '搜索'));
      await t.pumpAndSettle();
      expect(find.text('请填写标题'), findsOneWidget);
      expect(find.text('请填写艺术家'), findsOneWidget);
      expect(client.searches, 0);
      await t.enterText(find.byType(TextFormField).at(0), '旧标题');
      await t.enterText(find.byType(TextFormField).at(1), '旧艺术家');
      await t.tap(find.widgetWithText(TextButton, '搜索'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('163 搜索失败，请重试'), 250, scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first);
      expect(find.text('163 搜索失败，请重试'), findsOneWidget);
      await t.ensureVisible(find.text('保留：未提供').first);
      expect(find.text('保留：未提供'), findsWidgets);
      expect(find.text('新标题'), findsOneWidget);
      await t.ensureVisible(find.text('新标题'));
      await t.drag(find.byType(CustomScrollView), const Offset(0,120));
      await t.pumpAndSettle();
      await t.tap(find.text('新标题')); 
      await t.pumpAndSettle();
      final chip = t.widget<ChoiceChip>(
        find.ancestor(of: find.text('新标题'), matching: find.byType(ChoiceChip)),
      );
      expect(chip.selected, true);
      expect(d.fields['title'], '');
    },
  );
  test('album metadata is filtered to selected album and other fields remain global', () {
    const a = SongCandidate(song, {'album': 'A', 'date': '2001-01-01'});
    const b = SongCandidate(song, {'album': 'B', 'date': '2020-01-01'});
    expect(candidatesForSongField([a, b], 'date', 'A'), [a]);
    expect(candidatesForSongField([a, b], 'tracknumber', 'B'), [b]);
    expect(candidatesForSongField([a, b], 'title', 'A'), [a, b]);
  });
  test('field ranking rewards agreement with a bounded bonus and removes duplicate tracks', () {
    SongCandidate c(String id, String value, double score) => SongCandidate(
      CoverCandidate(
        source: 'qq',
        id: id,
        title: '',
        artist: '',
        album: '',
        artwork: '',
        score: score,
      ),
      {'title': value},
    );
    final ranked = rankSongField([
      c('1', 'A', 90),
      c('2', 'A', 90),
      c('3', 'B', 91),
      c('4', 'C', 20),
      c('5', 'C', 20),
    ], 'title');
    expect(ranked.first.value, 'A');
    expect(ranked.last.value, 'C');
    expect(
      rankSongField([c('1', 'A', 90), c('1', 'A', 90)], 'title').single.score,
      90,
    );
    expect(ranked.every((r) => r.score >= 0 && r.score <= 100), true);
  });
}
