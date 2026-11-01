import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/cover_search.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/music_share.dart';
import 'package:musiccardx/netease_share_fallback.dart';
import 'package:musiccardx/song_search.dart';
import 'package:musiccardx/song_search_page.dart';

CoverCandidate song(double score, {String source = '163', String art = ''}) =>
    CoverCandidate(
      source: source,
      id: '123',
      title: '歌曲',
      artist: '艺术家',
      album: '专辑',
      artwork: art,
      score: score,
    );
ShareResult parsed({
  String platform = 'netease',
  String cover = '',
  Map<String, String> fields = const {},
}) => ShareResult(
  SongCandidate(song(100, source: platform, art: cover), {
    'title': '歌曲',
    'artist': '艺术家',
    'album': '专辑',
    ...fields,
  }),
  cover,
  platform,
  [],
);

class Songs extends SongSearchClient {
  final double score;
  final bool fail;
  int calls = 0, detailCalls = 0;
  Songs(this.score, {this.fail = false});
  @override
  Future<List<CoverCandidate>> searchSource(
    String source,
    String title,
    String artist,
    String album,
    String region,
    CoverCancel cancel,
  ) async {
    calls++;
    expect(source, '163');
    cancel.check();
    if (fail) throw Exception('offline');
    return [song(score)];
  }

  @override
  Future<SongCandidate> details(
    CoverCandidate s,
    String region,
    CoverCancel cancel,
  ) async {
    detailCalls++;
    cancel.check();
    return SongCandidate(s, {
      'discnumber': '1',
      'totaldiscs': '2',
      'tracknumber': '8',
      'totaltracks': '10',
    });
  }
}

class Covers extends CoverSearchClient {
  final double score;
  int calls = 0;
  Covers(this.score);
  @override
  Future<List<CoverCandidate>> search({
    required String title,
    required String artist,
    required String album,
    required Set<String> enabled,
    required String region,
    required CoverCancel cancel,
    int duration = 0,
    required void Function(List<CoverCandidate>, Map<String, String>) onUpdate,
  }) async {
    calls++;
    expect(enabled, {'163'});
    cancel.check();
    return [song(score, art: 'https://p1.music.126.net/test.jpg')];
  }
}

class Resolver extends MusicShareService {
  final ShareResult result;
  Resolver(this.result);
  @override
  Future<List<ShareResult>> resolve(String raw, CoverCancel c) async => [
    result,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(CardDocument.initialize);
  for (final score in [79.9, 80.0, 99.999, 100.0]) {
    test('missing-only track fallback boundary $score', () async {
      final songs = Songs(score), covers = Covers(99);
      final f = NeteaseShareFallback(songs: songs, covers: covers);
      final r = await f.complete(
        parsed(fields: {'totaltracks': '12'}),
        'cn',
        CoverCancel(),
      );
      expect(r.candidate.fields['totaltracks'], '12');
      expect(r.candidate.fields['tracknumber'], score >= 80 ? '8' : isNull);
      expect(
        r.candidate.uncertainFields.contains('tracknumber'),
        score >= 80 && score < 100,
      );
      expect(r.cover, '');
      expect(r.candidate.song.id, '123');
      if (score >= 80) {
        expect(
          rankSongField([r.candidate], 'tracknumber').single.uncertain,
          score < 100,
        );
        expect(r.candidate.fieldScores['tracknumber'], score);
      }
      f.close();
    });
  }
  test('fallback cover requires 100, original cover and complete fields skip searches', () async {
    final songs = Songs(100), covers = Covers(100);
    final f = NeteaseShareFallback(songs: songs, covers: covers);
    final complete = parsed(
      cover: 'original',
      fields: {for (final k in shareTrackFields) k: '1'},
    );
    expect(
      identical(await f.complete(complete, 'cn', CoverCancel()), complete),
      true,
    );
    expect(songs.calls, 0);
    expect(covers.calls, 0);
    final filled = await f.complete(parsed(), 'cn', CoverCancel());
    expect(filled.cover, contains('music.126.net'));
    expect(filled.candidate.song.artwork, filled.cover);
    expect(filled.candidate.uncertainFields, isEmpty);
    f.close();
  });
  test('other platforms never search; search failures preserve direct fields and cover fallback still runs', () async {
    final songs = Songs(100, fail: true), covers = Covers(100);
    final f = NeteaseShareFallback(songs: songs, covers: covers);
    final qq = parsed(platform: 'qq');
    expect(identical(await f.complete(qq, 'cn', CoverCancel()), qq), true);
    expect(songs.calls, 0);
    final r = await f.complete(
      parsed(fields: {'tracknumber': '3'}),
      'cn',
      CoverCancel(),
    );
    expect(r.candidate.fields['tracknumber'], '3');
    expect(r.cover, isNotEmpty);
    expect(r.warnings.join(), contains('补全失败'));
    f.close();
  });
  test('cancellation propagates and verified direct data removes uncertainty for an equal value', () async {
    final f = NeteaseShareFallback(songs: Songs(90), covers: Covers(100));
    final c = CoverCancel()..cancel();
    await expectLater(
      f.complete(parsed(), 'cn', c),
      throwsA(isA<CoverCancelled>()),
    );
    final option = rankSongField([
      SongCandidate(
        song(90),
        {'tracknumber': '8'},
        fieldScores: {'tracknumber': 90},
        uncertainFields: {'tracknumber'},
      ),
      SongCandidate(song(100, source: 'netease'), {'tracknumber': '8'}),
    ], 'tracknumber').single;
    expect(option.uncertain, false);
    f.close();
  });
  for (final coverScore in [99.0, 100.0]) {
    testWidgets(
      'uncertain values remain numeric on apply; cover button threshold $coverScore',
      (t) async {
        t.view.physicalSize = const Size(900, 1800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final fallback = NeteaseShareFallback(
          songs: Songs(90),
          covers: Covers(coverScore),
        );
        Map<String, dynamic>? applied;
        await t.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('打开'),
                  onPressed: () async {
                    applied = await Navigator.push<Map<String, dynamic>>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SongSearchPage(
                          document: CardDocument.fresh()..fields.clear(),
                          onSettings: () async {},
                          initialShareText: 'link',
                          shareService: Resolver(
                            parsed(fields: {'totaltracks': '12'}),
                          ),
                          shareFallback: fallback,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('打开'));
        await t.pumpAndSettle();
        await t.tap(find.text('解析'));
        await t.pumpAndSettle();
        expect(find.text('8 存疑'), findsOneWidget);
        expect(
          find.text('查看封面'),
          coverScore == 100 ? findsOneWidget : findsNothing,
        );
        final uncertain = t.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, '8 存疑'),
        );
        final certain = t.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, '12'),
        );
        expect(
          uncertain.backgroundColor!.computeLuminance(),
          greaterThan(certain.backgroundColor!.computeLuminance()),
        );
        await t.tap(find.byTooltip('应用选中信息'));
        await t.pumpAndSettle();
        expect(applied!['tracknumber'], '8');
        expect(applied!['totaltracks'], '12');
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
    );
  }
}
