import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:musiccardx/cover_search.dart';
import 'package:musiccardx/cover_search_page.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/export_filename.dart';

const cover = CoverCandidate(
  source: 'apple',
  id: '1',
  title: 'Song',
  artist: 'Singer',
  album: 'Album',
  albumId: '1',
  artwork: 'https://is1-ssl.mzstatic.com/image/thumb/Music126/a/100x100bb.jpg',
);

class FakeSearch extends CoverSearchClient {
  final requests = <int>[];
  final queries = <String>[];
  bool fail = false;
  @override
  Future<List<CoverCandidate>> searchSource(
    String source,
    String query,
    String region,
    CoverCancel cancel,
  ) async {
    cancel.check();
    queries.add('$source:$query');
    return [cover];
  }

  @override
  Future<Uint8List> artwork(
    CoverCandidate candidate,
    int size,
    CoverCancel cancel, {
    void Function(int, int)? progress,
  }) async {
    cancel.check();
    requests.add(size);
    if (fail) throw const FormatException('download failed');
    final dimension = size == 150 ? 32 : 400;
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: dimension, height: dimension)),
    );
    progress?.call(bytes.length, bytes.length);
    return bytes;
  }
}

class LowSearch extends FakeSearch {
  @override
  Future<List<CoverCandidate>> searchSource(
    String source,
    String query,
    String region,
    CoverCancel cancel,
  ) async => [
    CoverCandidate(
      source: 'apple',
      id: 'low',
      title: 'ZZZZ',
      artist: 'QQQQ',
      album: 'VVVV',
      artwork: cover.artwork,
    ),
  ];
}

class PartialSearch extends FakeSearch {
  @override
  Future<List<CoverCandidate>> searchSource(
    String source,
    String query,
    String region,
    CoverCancel cancel,
  ) async {
    if (source == '163') throw const FormatException('source unavailable');
    return super.searchSource(source, query, region, cancel);
  }
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(CardDocument.initialize);
  test('three provider response shapes and static artwork validation', () {
    final a = CoverSearchClient.parse('apple', {
      'results': [
        {
          'wrapperType': 'track',
          'kind': 'song',
          'trackId': 1,
          'trackName': 'Song',
          'artistName': 'Singer',
          'collectionName': 'Album',
          'artworkUrl100': cover.artwork,
        },
        {'wrapperType': 'track', 'kind': 'music-video', 'trackName': 'Video'},
      ],
    });
    expect(a.single.title, 'Song');
    final n = CoverSearchClient.parse('163', {
      'code': 200,
      'result': {
        'songs': [
          {
            'id': 2,
            'name': '歌曲',
            'ar': [
              {'name': '歌手'},
            ],
            'al': {'id': 3, 'name': '专辑'},
            'dt': 1000,
            'alia': ['alias'],
          },
        ],
      },
    });
    expect(n.single.artist, '歌手');
    expect(n.single.albumId, '3');
    expect(n.single.aliases, ['alias']);
    final w = CoverSearchClient.parse('appleweb', {
      'results': {
        'songs': {
          'data': [
            {
              'id': 'x',
              'attributes': {
                'name': 'Song',
                'artistName': 'Singer',
                'albumName': 'Album',
                'artwork': {
                  'url': 'https://is1-ssl.mzstatic.com/image/thumb/Music/a/{w}x{h}bb.jpg',
                },
              },
            },
          ],
        },
      },
    });
    expect(w.single.title, 'Song');
    expect(
      CoverSearchClient.isAppleArtwork('https://example.com/Music/100x100.jpg'),
      isFalse,
    );
    expect(
      CoverSearchClient.isAppleArtwork(
        'https://is1-ssl.mzstatic.com/video/100x100.jpg',
      ),
      isFalse,
    );
  });
  test('artwork URL sizes support zero and do not invent max dimensions', () {
    final templated = CoverSearchClient.artworkUrls(
      cover.artwork.replaceFirst('100x100', '{w}x{h}'),
      150,
      apple: true,
    );
    expect(templated.first.path, endsWith('/150x150.png'));
    final small = CoverSearchClient.artworkUrls(
      cover.artwork,
      150,
      apple: true,
    );
    expect(small.first.path, endsWith('/150x150.png'));
    final large = CoverSearchClient.artworkUrls(cover.artwork, 0, apple: true);
    expect(large.first.path, endsWith('/4000x4000.png'));
    expect(large.any((u) => u.path.endsWith('/1200x1200bb.jpg')), isTrue);
    expect(
      CoverSearchClient.artworkUrls(
        'https://p1.music.126.net/a.jpg',
        1000,
        apple: false,
      ).first.queryParameters['param'],
      '1000y1000',
    );
    expect(
      CoverSearchClient.artworkUrls(
        'https://p1.music.126.net/a.jpg',
        0,
        apple: false,
      ).single.queryParameters,
      isEmpty,
    );
  });
  test('match scoring penalizes versions and preserves manual candidates', () {
    expect(textSimilarity('Ｓｏｎｇ', 'song'), 1);
    expect(textSimilarity('Beyoncé', 'Beyonce'), 1);
    final regular = matchScore(cover, 'Song', 'Singer', 'Album');
    expect(regular, 100);
    const live = CoverCandidate(
      source: '163',
      id: '2',
      title: 'Song (Live)',
      artist: 'Singer',
      album: 'Album',
      artwork: '',
    );
    expect(matchScore(live, 'Song', 'Singer', 'Album'), lessThan(regular));
    expect(
      matchScore(cover, 'Completely different', 'Other', 'Other'),
      lessThan(55),
    );
  });
  test('source completion is incremental; album duplicates collapse', () async {
    final c = FakeSearch();
    final updates = <int>[];
    try {
      final rows = await c.search(
        title: 'Song',
        artist: 'Singer',
        album: 'Album',
        enabled: {'apple'},
        region: 'cn',
        cancel: CoverCancel(),
        onUpdate: (r, s) => updates.add(r.length),
      );
      expect(rows.single.score, 100);
      expect(c.queries.length, 1);
      expect(updates, [0, 1]);
      final cancel = CoverCancel()..cancel();
      await expectLater(
        c.searchSource('apple', 'q', 'cn', cancel),
        throwsA(isA<CoverCancelled>()),
      );
    } finally {
      c.close();
    }
  });
  test(
    'all configuration defaults roundtrip and new preferences are validated',
    () {
      final d = CardDocument.fresh();
      d.data.addAll({
        'previewPinned': false,
        'imageFolder': '/storage/emulated/0/Pictures/MCX',
        'imageFilename': '[%title%]-%seed%',
        'imageFormat': 'jpg',
        'jpegQuality': 83,
        'monet': true,
        'displayFontName': 'font-id',
        'coverSearchPreviewSize': 0,
        'coverSearchDownloadSize': 2000,
        'coverSearch_163': false,
        'coverSearch_apple': false,
        'coverSearch_appleweb': true,
        'coverSearchRegion': 'jp',
        'fontPreferences': {
          'mode': 'ezcd',
          'tree': 'path:/storage/fonts',
          'sample': '自定义ABC',
          'previewSize': 88.0,
        },
      });
      d.data['coverShape'] = 'quadratic';
      d.data['coverShapeParameters'] = {
        'quadratic': {'coverCornerRadius': 20, 'cornerTension': .3},
      };
      final restored = CardDocument.fromJson(jsonDecode(jsonEncode(d.data)));
      for (final key in d.data.keys.where((k) => k != 'fields')) {
        expect(restored.data[key], d.data[key], reason: key);
      }
      final legacy = Map<String, dynamic>.from(d.data)
        ..remove('coverSearchPreviewSize')
        ..remove('fontPreferences');
      expect(CardDocument.fromJson(legacy).data['coverSearchPreviewSize'], 150);
      final invalid = Map<String, dynamic>.from(d.data)
        ..['coverSearchRegion'] = 'bad'
        ..['coverSearchDownloadSize'] = -3;
      final clean = CardDocument.fromJson(invalid);
      expect(clean.text('coverSearchRegion'), 'cn');
      expect(clean.data['coverSearchDownloadSize'], 0);
      expect(
        exportFilename(d, 'png', suffix: '-cover'),
        endsWith('-cover.png'),
      );
    },
  );
  test('a failed source leaves successful results available', () async {
    final c = PartialSearch();
    Map<String, String> states = {};
    try {
      final rows = await c.search(
        title: 'Song',
        artist: 'Singer',
        album: 'Album',
        enabled: {'163', 'apple'},
        region: 'cn',
        cancel: CoverCancel(),
        onUpdate: (r, s) {
          states = s;
        },
      );
      expect(rows.single.title, 'Song');
      expect(states['163'], startsWith('失败'));
      expect(states['apple'], '已完成');
    } finally {
      c.close();
    }
  });
  test('cover loader reuses previews, supports zero, and clamps oversize responses', () async {
    final client = FakeSearch();
    final loader = CoverLoader(client);
    final cancel = CoverCancel();
    try {
      final a = await loader.load(cover, 150, cancel);
      expect(a.width, 32);
      expect(identical(await loader.load(cover, 150, cancel), a), isTrue);
      expect(client.requests, [150]);
      final max = await loader.load(cover, 0, cancel);
      expect(max.width, 400);
      expect(client.requests, [150, 0]);
      final resized = await CoverAsset.inspect(max.bytes, maxSide: 100);
      expect(identical(resized.bytes, max.bytes), isTrue);
      expect(resized.width, 400);
      expect(resized.height, 400);
      cancel.cancel();
      await expectLater(
        loader.load(cover, 150, cancel),
        throwsA(isA<CoverCancelled>()),
      );
    } finally {
      client.close();
      loader.clear();
    }
  });
  test('adaptive grid uses two columns on phones and adjusts for devices', () {
    expect(coverGridColumns(380), 2);
    expect(coverGridColumns(290), 1);
    expect(coverGridColumns(800), 4);
  });
  testWidgets(
    'detail buttons save/use the current asset without implicit full download',
    (t) async {
      final c = FakeSearch();
      final actualLoader = CoverLoader(c);
      CoverAsset? saved, chosen;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  chosen = await Navigator.push<CoverAsset>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CoverDetailPage(
                        candidate: cover,
                        loader: actualLoader,
                        previewSize: 150,
                        downloadSize: 1000,
                        onSave: (a) async {
                          saved = a;
                          return true;
                        },
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await settle(t);
      expect(find.text('32×32'), findsOneWidget);
      expect(c.requests, [150]);
      expect(find.text('保存封面'), findsNothing);
      expect(find.text('使用此封面'), findsNothing);
      await t.tap(find.byTooltip('保存当前封面'));
      await settle(t);
      expect(saved!.width, 32);
      expect(c.requests, [150]);
      await t.tap(find.byTooltip('下载大图'));
      await settle(t);
      expect(c.requests, [150, 1000]);
      expect(find.text('400×400'), findsOneWidget);
      await t.tap(find.byTooltip('保存当前封面'));
      await settle(t);
      expect(saved!.width, 400);
      await t.tap(find.byTooltip('使用此封面'));
      await settle(t);
      expect(chosen!.width, 400);
      c.close();
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'check downloads the large cover first and never applies a failed download',
    (t) async {
      final c = FakeSearch();
      final loader = CoverLoader(c);
      CoverAsset? chosen;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  chosen = await Navigator.push<CoverAsset>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CoverDetailPage(
                        candidate: cover,
                        loader: loader,
                        previewSize: 150,
                        downloadSize: 1000,
                        onSave: (_) async => true,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await settle(t);
      expect(c.requests, [150]);
      c.fail = true;
      await t.tap(find.byTooltip('使用此封面'));
      await settle(t);
      expect(c.requests, [150, 1000]);
      expect(chosen, isNull);
      expect(find.byType(CoverDetailPage), findsOneWidget);
      expect(find.text('32×32'), findsOneWidget);
      c.fail = false;
      await t.tap(find.byTooltip('使用此封面'));
      await settle(t);
      expect(c.requests, [150, 1000, 1000]);
      expect(chosen!.width, 400);
      expect(find.byType(CoverDetailPage), findsNothing);
      c.close();
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );
  testWidgets('low-score candidates load previews only after manual download', (
    t,
  ) async {
    final d = CardDocument.fresh();
    d.fields.addAll({'title': 'Song', 'artist': 'Singer', 'album': 'Album'});
    d.data['coverSearch_163'] = false;
    final c = LowSearch();
    await t.pumpWidget(
      MaterialApp(
        home: CoverSearchPage(
          document: d,
          client: c,
          onSettings: () async {},
          onSave: (_) async => true,
        ),
      ),
    );
    await t.tap(find.widgetWithText(TextButton, '搜索'));
    await settle(t);
    expect(c.requests, isEmpty);
    await t.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await settle(t);
    await t.tap(find.byTooltip('下载预览图'));
    await settle(t);
    expect(c.requests, [150]);
    await t.pumpWidget(const SizedBox());
    await settle(t);
  });
  testWidgets('phone grid stays usable with enlarged text', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 850));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final d = CardDocument.fresh();
    d.fields.addAll({'title': 'Song', 'artist': 'Singer', 'album': 'Album'});
    d.data['coverSearch_163'] = false;
    final c = FakeSearch();
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: CoverSearchPage(
          document: d,
          client: c,
          onSettings: () async {},
          onSave: (_) async => true,
        ),
      ),
    );
    await t.ensureVisible(find.widgetWithText(TextButton, '搜索'));
    await t.tap(find.widgetWithText(TextButton, '搜索'));
    await settle(t);
    final grid = t.widget<SliverGrid>(find.byType(SliverGrid));
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      2,
    );
    await t.scrollUntilVisible(
      find.text('Song').last,
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await settle(t);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await settle(t);
  });
  testWidgets(
    'search page keeps form metadata separate and persists dimensions',
    (t) async {
      final d = CardDocument.fresh();
      d.fields['title'] = 'Song';
      d.fields['artist'] = 'Singer';
      d.fields['album'] = 'Album';
      final c = FakeSearch();
      var saves = 0;
      await t.pumpWidget(
        MaterialApp(
          home: CoverSearchPage(
            document: d,
            client: c,
            onSettings: () async {
              saves++;
            },
            onSave: (_) async => true,
          ),
        ),
      );
      await t.enterText(find.widgetWithText(TextFormField, '标题'), 'Different');
      await t.enterText(find.widgetWithText(TextFormField, '预览封面尺寸'), '0');
      await t.tap(find.widgetWithText(TextButton, '搜索'));
      await settle(t);
      expect(d.fields['title'], 'Song');
      expect(d.data['coverSearchPreviewSize'], 0);
      expect(saves, greaterThan(0));
      expect(c.queries.first, contains('Different'));
      final grid = t.widget<SliverGrid>(find.byType(SliverGrid));
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        4,
      );
      await t.pumpWidget(const SizedBox());
      await settle(t);
      expect(t.takeException(), isNull);
    },
  );
}
