import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/music_share.dart';
import 'package:musiccardx/cover_search.dart';

void main() {
  test('numeric alias alone remains an unlabelled ID', () {
    expect(shareLinks('163').map(sharePlatform).toSet(), {
      'netease',
      'qq',
      'kugou',
      'kuwo',
      'bodian',
      'soda',
    });
  });
  test(
    'unlabelled ID reaches all platform resolvers despite failures',
    () async {
      final service = _ProbeService();
      try {
        await expectLater(
          service.resolve('2617714044', CoverCancel()),
          throwsFormatException,
        );
        expect(service.attempted.toSet(), {
          'netease',
          'qq',
          'kugou',
          'kuwo',
          'bodian',
          'soda',
        });
      } finally {
        service.close();
      }
    },
  );
  for (final alias in shareAliases.keys) {
    for (final gap in ['', ' ', '   ', '\t', '\n\n']) {
      if (alias == '163' && gap.isEmpty) continue;
      for (final reverse in [false, true]) {
        final input = reverse
            ? '2617714044$gap$alias'
            : '$alias${gap}2617714044';
        test(input, () {
          final links = shareLinks(input);
          expect(links.length, 1);
          expect(sharePlatform(links.single), shareAliases[alias]);
        });
      }
    }
  }
  test('unlabelled numeric queries every platform', () {
    expect(shareLinks('2617714044').map(sharePlatform).toSet(), {
      'netease',
      'qq',
      'kugou',
      'kuwo',
      'bodian',
      'soda',
    });
  });
  test('user examples', () {
    for (final s in [
      'wyy music.163.com/#/song?id=2617714044',
      '163 2617714044',
      '网易 song?id=2617714044',
      '网易 =2617714044',
      '2617714044 网易云',
      'WYY\n\t2617714044',
    ]) {
      final r = shareLinks(s);
      expect(r.length, 1, reason: s);
      expect(sharePlatform(r.single), 'netease');
    }
  });
  test('foreign URLs do not leak numeric query ids', () {
    expect(shareLinks('https://y.qq.com.evil.test/song?id=123456'), isEmpty);
  });
  test('distinct platforms retained, equivalent urls deduplicated', () {
    expect(
      shareLinks(
        'music.163.com/#/song?id=123456\nhttps://music.163.com/song?id=123456',
      ).length,
      1,
    );
    expect(shareLinks('网易 123456\nQQ 234567').map(sharePlatform), [
      'netease',
      'qq',
    ]);
  });
}

class _ProbeService extends MusicShareService {
  final attempted = <String>[];
  @override
  Future<ShareResult> one(Uri original, dynamic cancel) async {
    attempted.add(sharePlatform(original)!);
    throw const FormatException('fixture miss');
  }
}
