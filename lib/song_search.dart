import 'dart:convert';
import 'dart:math' as math;

import 'cover_search.dart';

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : {};
List<dynamic> _list(dynamic v) => v is List ? v : [];
String _text(dynamic v) => v == null ? '' : '$v'.trim();

const songSearchFields = <String, String>{
  'title': '标题',
  'artist': '艺术家',
  'album': '专辑',
  'date': '完整日期',
  'discnumber': 'Disc',
  'totaldiscs': 'Disc总数',
  'tracknumber': 'Track',
  'totaltracks': 'Track总数',
};

class SongCandidate {
  final CoverCandidate song;
  final Map<String, String> fields;
  final String detailError;
  const SongCandidate(this.song, this.fields, {this.detailError = ''});
  String get key => '${song.source}:${song.id}';
}

/// Search results never change a user's fields until explicitly applied.
/// Missing remote values preserve the user's existing values, including extra tags.
Map<String, dynamic> applySongCandidate(
  Map<String, dynamic> original,
  SongCandidate candidate,
) => {
  ...original,
  for (final e in candidate.fields.entries)
    if (songSearchFields.containsKey(e.key) && e.value.trim().isNotEmpty)
      e.key: e.value.trim(),
};

class SongSearchClient {
  final CoverSearchClient covers;
  SongSearchClient({CoverSearchClient? covers})
    : covers = covers ?? CoverSearchClient(metadataOnly: true);
  static const sources = {
    '163': '163',
    'apple': 'Apple',
    'appleweb': 'Apple不限速',
    'qq': 'QQ音乐',
  };
  void close() => covers.close();

  static List<CoverCandidate> parseQQ(Map<String, dynamic> root) {
    final response = _map(root['req_0']);
    if (root['code'] != 0 || response['code'] != 0) {
      throw const FormatException('QQ音乐搜索失败');
    }
    final data = _map(response['data']);
    final rows = _list(_map(_map(data['body'])['song'])['list']);
    return [
      for (final raw in rows)
        if (_text(_map(raw)['mid']).isNotEmpty &&
            _text(_map(raw)['name'] ?? _map(raw)['title']).isNotEmpty)
          qqSong(_map(raw)),
    ];
  }

  static List<CoverCandidate> parseQQLegacy(Map<String, dynamic> root) {
    if (root['code'] != 0) throw const FormatException('QQ音乐搜索失败');
    return [
      for (final v in _list(_map(_map(root['data'])['song'])['list']))
        if (_text(_map(v)['songmid']).isNotEmpty)
          qqSong({
            ..._map(v),
            'mid': _map(v)['songmid'],
            'name': _map(v)['songname'],
            'album': {'mid': _map(v)['albummid'], 'name': _map(v)['albumname']},
            'time_public': _map(v)['pubtime'] is num
                ? (_map(v)['pubtime'] as num) * 1000
                : null,
          }),
    ];
  }

  static CoverCandidate qqSong(Map<String, dynamic> row) {
    final album = _map(row['album']);
    return CoverCandidate(
      source: 'qq',
      displaySource: 'QQ音乐',
      id: _text(row['mid']),
      title: _text(row['name'] ?? row['title']),
      artist: _list(row['singer'])
          .map((v) => _text(_map(v)['name']))
          .where((s) => s.isNotEmpty)
          .join(' / '),
      album: _text(album['name'] ?? album['title']),
      albumId: _text(album['mid']),
      artwork: '',
      duration: (int.tryParse('${row['interval']}') ?? 0) * 1000,
      metadata: songMetadataValues(
        date: row['time_public'] ?? album['time_public'],
        // QQ index_cd is zero-based. index_album is already one-based.
        disc: row['index_cd'] is num
            ? (row['index_cd'] as num).toInt() + 1
            : null,
        track: row['index_album'],
      ),
    );
  }

  Future<Map<String, dynamic>> _qq(
    String module,
    String method,
    Map<String, dynamic> param,
    CoverCancel cancel,
  ) async {
    final root = await covers.http.json(
      Uri.https('u.y.qq.com', '/cgi-bin/musicu.fcg', {
        'format': 'json',
        'data': jsonEncode({
          'comm': {'ct': 19, 'cv': 1859, 'uin': '0', 'format': 'json'},
          'req_0': {'module': module, 'method': method, 'param': param},
        }),
      }),
      cancel,
      headers: {'Referer': 'https://y.qq.com/'},
    );
    if (root['code'] != 0 || _map(root['req_0'])['code'] != 0) {
      throw const FormatException('QQ音乐接口暂不可用');
    }
    return root;
  }

  Future<List<CoverCandidate>> searchSource(
    String source,
    String title,
    String artist,
    String album,
    String region,
    CoverCancel cancel,
  ) async {
    final query = [
      title,
      artist,
      album,
    ].where((s) => s.trim().isNotEmpty).join(' ');
    List<CoverCandidate> rows;
    if (source == 'qq') {
      // Mobile search currently returns full matches where desktop can silently return none.
      rows = parseQQLegacy(
        await covers.http.json(
          Uri.https('c.y.qq.com', '/soso/fcgi-bin/search_for_qq_cp', {
            'w': query,
            'p': '1',
            'n': '30',
            'format': 'json',
          }),
          cancel,
          headers: {'Referer': 'https://y.qq.com/'},
        ),
      );
      if (rows.isEmpty) {
        rows = parseQQ(
          await _qq(
            'music.search.SearchCgiService',
            'DoSearchForQQMusicDesktop',
            {
              'remoteplace': 'txt.yqq.song',
              'query': title,
              'num_per_page': 30,
              'page_num': 1,
              'search_type': 0,
            },
            cancel,
          ),
        );
      }
    } else {
      rows = await covers.searchSource(source, query, region, cancel);
      if (rows.isEmpty && album.isNotEmpty) {
        rows = await covers.searchSource(
          source,
          '$title $artist',
          region,
          cancel,
        );
      }
    }
    final seen = <String>{};
    final scored =
        rows
            .where((r) => seen.add(r.id))
            .map((c) => c.scored(matchScore(c, title, artist, album)))
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    return scored.take(12).toList();
  }

  static Map<String, String> neteaseAlbum(
    Map<String, dynamic> root,
    String songId,
  ) {
    if (root['code'] != null && root['code'] != 200) {
      throw const FormatException('163专辑信息暂不可用');
    }
    final album = _map(root['album']);
    final songs = _list(root['songs'] ?? album['songs']).map(_map).toList();
    final song = songs.where((s) => _text(s['id']) == songId).firstOrNull ?? {};
    final out = songMetadataValues(
      date: album['publishTime'],
      disc: song['disc'] ?? song['cd'],
      track: song['no'] ?? song['trackNo'] ?? song['position'],
      tracks: album['size'] ?? album['trackCount'],
    );
    // Do not substitute list position for a real track number, or infer total discs.
    return out;
  }

  static Map<String, String> appleAlbum(
    Map<String, dynamic> root,
    String songId,
  ) {
    final album = _map(_list(root['data']).firstOrNull);
    final a = _map(album['attributes']);
    final tracks = _list(_map(_map(album['relationships'])['tracks'])['data'])
        .map(_map);
    final track = tracks.where((s) => _text(s['id']) == songId).firstOrNull;
    final t = _map(track?['attributes']);
    return songMetadataValues(
      date: t['releaseDate'] ?? a['releaseDate'],
      disc: t['discNumber'],
      discs: a['discCount'],
      track: t['trackNumber'],
      tracks: a['trackCount'],
    );
  }

  Future<SongCandidate> details(
    CoverCandidate song,
    String region,
    CoverCancel cancel,
  ) async {
    var metadata = <String, String>{...song.metadata};
    var error = '';
    try {
      if (song.source == '163' && RegExp(r'^\d+$').hasMatch(song.albumId)) {
        final root = await covers.http.json(
          Uri.https('music.163.com', '/api/album/${song.albumId}'),
          cancel,
          headers: {'Referer': 'https://music.163.com/'},
        );
        metadata.addAll(neteaseAlbum(root, song.id));
      } else if (song.source == 'appleweb' && song.albumId.isNotEmpty) {
        final fields = appleAlbum(
          await covers.appleCatalogAlbum(song.albumId, region, cancel),
          song.id,
        );
        // A track's exact release date takes precedence over its album's date.
        if (metadata.containsKey('date')) {
          fields.remove('date');
        }
        metadata.addAll(fields);
      } else if (song.source == 'qq') {
        final root = await _qq(
          'music.pf_song_detail_svr',
          'get_song_detail_yqq',
          {'song_mid': song.id},
          cancel,
        );
        final data = _map(_map(root['req_0'])['data']);
        metadata.addAll(qqSong(_map(data['track_info'])).metadata);
        final pub = _list(_map(_map(data['info'])['pub_time'])['content']);
        if (pub.isNotEmpty) {
          metadata.addAll(songMetadataValues(date: _map(pub.first)['value']));
        }
      }
    } on CoverCancelled {
      rethrow;
    } catch (_) {
      error = '部分信息未能获取';
    }
    cancel.check();
    return SongCandidate(song, {
      'title': song.title,
      'artist': song.artist,
      'album': song.album,
      ...metadata,
    }, detailError: error);
  }
}

class SongFieldOption {
  final String value;
  final double score;
  final int count;
  const SongFieldOption(this.value, this.score, this.count);
}

/// Repeated rows from the same source/track count once. A bounded bonus rewards
/// agreement without letting many weak matches defeat one strong match.
List<SongFieldOption> rankSongField(
  Iterable<SongCandidate> candidates,
  String key,
) {
  final groups = <String, Map<String, double>>{};
  for (final c in candidates) {
    final value = (c.fields[key] ?? '').trim();
    final group = groups.putIfAbsent(value, () => {});
    group[c.key] = math.max(group[c.key] ?? 0, c.song.score.clamp(0, 100));
  }
  final options = <SongFieldOption>[];
  for (final e in groups.entries) {
    final scores = e.value.values.toList();
    final best = scores.reduce(math.max);
    final mean = scores.reduce((a, b) => a + b) / scores.length;
    final quality = .85 * best + .15 * mean;
    final agreement = 1 - math.exp(-(scores.length - 1) / 2);
    final score = quality + (100 - quality) * .3 * agreement;
    options.add(SongFieldOption(e.key, score, scores.length));
  }
  options.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : a.value.compareTo(b.value);
  });
  return options;
}

const albumDependentFields = {
  'date',
  'discnumber',
  'totaldiscs',
  'tracknumber',
  'totaltracks',
};
Iterable<SongCandidate> candidatesForSongField(
  Iterable<SongCandidate> candidates,
  String key,
  String album,
) => albumDependentFields.contains(key)
    ? candidates.where((c) => (c.fields['album'] ?? '').trim() == album.trim())
    : candidates;
