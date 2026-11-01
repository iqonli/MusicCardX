import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cover_search.dart';
import 'song_search.dart';

Map<String, dynamic> sm(dynamic x) =>
    x is Map ? Map<String, dynamic>.from(x) : {};
List<dynamic> sl(dynamic x) => x is List ? x : [];
String st(dynamic x) => x == null ? '' : '$x';
int sn(dynamic x) => int.tryParse(st(x)) ?? 0;
const sharePlatforms = '网易云音乐、QQ音乐、酷狗音乐、酷我音乐、波点音乐、汽水音乐';
String? sharePlatform(Uri u) {
  final h = u.host.toLowerCase();
  bool host(String s) => h == s || h.endsWith('.$s');
  if (host('163cn.tv') || host('163cn.link') || host('music.163.com')) {
    return 'netease';
  }
  if (host('y.qq.com')) return 'qq';
  if (host('kugou.com')) return 'kugou';
  if (h == 'h5app.kuwo.cn') return 'bodian';
  if (host('kuwo.cn')) return 'kuwo';
  if (h == 'qishui.douyin.com' ||
      h == 'music.douyin.com' ||
      host('qishui.com')) {
    return 'soda';
  }
  return null;
}

List<Uri> shareLinks(String raw) {
  final clean = raw
      .replaceAll('&amp;', '&')
      .replaceAll(r'\&', '&')
      .replaceAll(r'\_', '_');
  final seen = <String>{};
  final out = <Uri>[];
  for (final m in RegExp(
    r'''https?://[^\s<>\[\]()"'，。；、]+''',
  ).allMatches(clean)) {
    final text = m[0]!.replaceFirst(RegExp(r'[.,;!！）】]+$'), '');
    final u = Uri.tryParse(text);
    if (u != null && sharePlatform(u) != null && seen.add(u.toString())) {
      out.add(u);
    }
  }
  return out;
}

/// Extract a JSON object without evaluating JavaScript or truncating nested braces.
String assignedObject(String html, String marker) {
  final at = html.indexOf(marker);
  if (at < 0) throw const FormatException('页面未提供歌曲数据');
  final start = html.indexOf('{', at + marker.length);
  if (start < 0) throw const FormatException('页面数据为空');
  int depth = 0;
  String quote = '';
  bool escaped = false;
  for (int i = start; i < html.length; i++) {
    final c = html[i];
    if (quote.isNotEmpty) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == quote) {
        quote = '';
      }
      continue;
    }
    if (c == '"' || c == "'") {
      quote = c;
      continue;
    }
    if (c == '{') {
      depth++;
      if (depth > 100) throw const FormatException('嵌套过深');
    }
    if (c == '}' && --depth == 0) return html.substring(start, i + 1);
  }
  throw const FormatException('页面数据不完整');
}

/// Tokenize only quoted strings; remaining syntax must pass strict JSON decoding.
dynamic looseJson(String text) {
  if (text.length > 3000000) throw const FormatException('响应过大');
  final out = StringBuffer();
  for (int i = 0; i < text.length; i++) {
    final q = text[i];
    if (q != '"' && q != "'") {
      out.write(q);
      continue;
    }
    final b = StringBuffer();
    bool ended = false;
    while (++i < text.length) {
      final c = text[i];
      if (c == q) {
        ended = true;
        break;
      }
      if (c == r'\') {
        if (++i >= text.length) break;
        final e = text[i];
        if (e == 'u' && i + 4 < text.length) {
          b.writeCharCode(int.parse(text.substring(i + 1, i + 5), radix: 16));
          i += 4;
        } else {
          b.write(
            {'n': '\n', 'r': '\r', 't': '\t', 'b': '\b', 'f': '\f'}[e] ?? e,
          );
        }
      } else {
        b.write(c);
      }
    }
    if (!ended) throw const FormatException('字符串不完整');
    out.write(jsonEncode(b.toString()));
  }
  return jsonDecode(out.toString());
}

class ShareHttp {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  void close() => client.close(force: true);
  static bool allowed(Uri u) {
    if (u.userInfo.isNotEmpty || (u.hasPort && u.port != 80 && u.port != 443)) {
      return false;
    }
    final h = u.host.toLowerCase();
    final valid =
        sharePlatform(u) != null ||
        [
          'music.126.net',
          'gtimg.cn',
          'douyinpic.com',
        ].any((s) => h == s || h.endsWith('.$s'));
    final httpAllowed = [
      'search.kuwo.cn',
      'mobilecdn.kugou.com',
      'm.kugou.com',
      'imge.kugou.com',
    ].contains(h);
    return valid && (u.scheme == 'https' || u.scheme == 'http' && httpAllowed);
  }

  Future<(Uint8List, Uri)> read(
    Uri initial,
    CoverCancel cancel, {
    Map<String, dynamic>? post,
    bool stopAtIdentity = false,
    Map<String, String> headers = const {},
  }) async {
    var u = initial;
    final seen = <String>{};
    for (int hop = 0; hop < 7; hop++) {
      cancel.check();
      if (!allowed(u) || !seen.add(u.toString())) {
        throw const FormatException('链接或跳转不受支持');
      }
      final req = await client.openUrl(post == null ? 'GET' : 'POST', u);
      req.followRedirects = false;
      req.headers.set('User-Agent', 'Mozilla/5.0 MusicCardX/1.4.5');
      for (final e in headers.entries) {
        req.headers.set(e.key, e.value);
      }
      if (post != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(post));
      }
      final response = await req.close();
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value('location');
        await response.drain<void>();
        if (location == null) break;
        u = u.resolve(location);
        if (u.scheme == 'http' && sharePlatform(u) == sharePlatform(initial)) {
          u = u.replace(scheme: 'https');
        }
        if (!allowed(u) || sharePlatform(u) != sharePlatform(initial)) {
          throw const FormatException('跳转平台不匹配');
        }
        if (stopAtIdentity &&
            (u.queryParameters.containsKey('songmid') ||
                u.queryParameters.containsKey('songid') ||
                u.queryParameters.containsKey('track_id') ||
                sharePlatform(u) == 'netease' &&
                    u.queryParameters.containsKey('id'))) {
          return (Uint8List(0), u);
        }
        post = null;
        continue;
      }
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final bytes = BytesBuilder(copy: false);
      int count = 0;
      await for (final chunk in response) {
        cancel.check();
        count += chunk.length;
        if (count > 32 * 1024 * 1024) {
          req.abort();
          throw const FormatException('响应过大');
        }
        bytes.add(chunk);
      }
      cancel.check();
      return (bytes.takeBytes(), u);
    }
    throw const FormatException('跳转次数过多');
  }

  Future<String> text(
    Uri u,
    CoverCancel c, {
    Map<String, dynamic>? post,
    Map<String, String> headers = const {},
  }) async => utf8.decode(
    (await read(
      u,
      c,
      post: post,
      headers: headers,
    ).timeout(const Duration(seconds: 30))).$1,
    allowMalformed: true,
  );
  Future<Map<String, dynamic>> json(
    Uri u,
    CoverCancel c, {
    Map<String, dynamic>? post,
    Map<String, String> headers = const {},
  }) async => sm(looseJson(await text(u, c, post: post, headers: headers)));
}

class ShareResult {
  final SongCandidate candidate;
  final String cover, platform;
  final List<String> warnings;
  const ShareResult(this.candidate, this.cover, this.platform, this.warnings);
}

/// Count positions only in a complete, identity-matched album, never search order.
Map<String, String> shareAlbum(
  List<Map<String, dynamic>> rows,
  String id,
  int count, {
  String idKey = 'id',
}) {
  final out = <String, String>{};
  if (count > 0) out['totaltracks'] = '$count';
  final index = rows.indexWhere(
    (r) => st(r[idKey]).toLowerCase() == id.toLowerCase(),
  );
  if (index < 0) return out;
  final row = rows[index];
  final explicit = sn(row['no'] ?? row['track']);
  if (explicit > 0) out['tracknumber'] = '$explicit';
  final disc = sn(row['disc']);
  if (disc > 0) out['discnumber'] = '$disc';
  final ids = rows.map((r) => st(r[idKey])).toSet();
  if (count <= 0 ||
      count != rows.length ||
      ids.length != count ||
      ids.contains('')) {
    return out;
  }
  out['tracknumber'] = '${index + 1}';
  final discs = rows.map((r) => sn(r['disc'])).toList();
  if (discs.every((d) => d > 0)) {
    final unique = discs.toSet().toList()..sort();
    if (unique.last == unique.length) {
      final d = discs[index];
      out['discnumber'] = '$d';
      out['totaldiscs'] = '${unique.length}';
      out['tracknumber'] =
          '${discs.take(index + 1).where((x) => x == d).length}';
      out['totaltracks'] = '${discs.where((x) => x == d).length}';
    }
  }
  // A supplied track number is usable if consistent; otherwise expose list ordering.
  return out;
}

class MusicShareService {
  final ShareHttp http;
  MusicShareService({ShareHttp? http}) : http = http ?? ShareHttp();
  void close() => http.close();
  Future<List<ShareResult>> resolve(String raw, CoverCancel cancel) async {
    final results = <ShareResult>[];
    final links = shareLinks(raw);
    if (links.isEmpty) throw const FormatException('未识别到支持的链接；酷狗裸数字码无法唯一确定歌曲');
    final errors = <String>[];
    for (final original in links.take(10)) {
      try {
        results.add(
          await one(original, cancel).timeout(const Duration(seconds: 75)),
        );
      } on CoverCancelled {
        rethrow;
      } catch (e) {
        errors.add('${sharePlatform(original)}：${conciseError(e)}');
        final hint = RegExp('《([^》]+)》').firstMatch(raw);
        if (links.length == 1 && hint != null) {
          final platform = sharePlatform(original)!;
          final title = hint[1]!;
          final song = CoverCandidate(
            source: 'hint-$platform',
            id: original.toString(),
            title: title,
            artist: '',
            album: '',
            artwork: '',
            score: 25,
            displaySource: '$platform 分享文案（未核验）',
          );
          results.add(
            ShareResult(SongCandidate(song, {'title': title}), '', platform, [
              '仅分享文案，身份尚未核验',
              conciseError(e),
            ]),
          );
        }
      }
    }
    if (results.isEmpty) throw FormatException(errors.join('\n'));
    return results;
  }

  Future<ShareResult> one(Uri original, CoverCancel c) async {
    final platform = sharePlatform(original)!;
    var u = original;
    String html = '';
    if ([
      '163cn.tv',
      '163cn.link',
      'c6.y.qq.com',
      't1.kugou.com',
      'qishui.douyin.com',
    ].contains(u.host)) {
      // Each redirect is validated, and complete source text remains in the UI.
      final response = await http
          .read(u, c, stopAtIdentity: true)
          .timeout(const Duration(seconds: 30));
      u = response.$2;
      html = utf8.decode(response.$1, allowMalformed: true);
    }
    final fragment = Uri.tryParse(u.fragment);
    final q = {
      ...u.queryParameters,
      if (fragment != null) ...fragment.queryParameters,
    };
    final fields = <String, String>{};
    String id = '', cover = '', albumId = '';
    final warnings = <String>[];
    void basic(
      Map<String, dynamic> row, {
      String title = 'name',
      String artist = 'artist',
      String album = 'album',
      String pic = 'cover',
    }) {
      for (final e in {
        'title': row[title],
        'artist': row[artist],
        'album': row[album],
      }.entries) {
        if (st(e.value).isNotEmpty) fields[e.key] = st(e.value);
      }
      cover = st(row[pic]);
    }

    if (platform == 'netease') {
      id = q['id'] ?? RegExp(r'/song/(\d+)').firstMatch(u.path)?[1] ?? '';
      if (!RegExp(r'^\d+$').hasMatch(id)) {
        throw const FormatException('未确认网易云歌曲ID');
      }
      final d = await http.json(
        Uri.https('music.163.com', '/api/song/detail/', {'ids': '[$id]'}),
        c,
      );
      final row = sl(d['songs'])
          .map(sm)
          .where((s) => st(s['id']) == id)
          .firstOrNull;
      if (row == null) throw const FormatException('歌曲身份不匹配');
      final al = sm(row['album'] ?? row['al']);
      fields.addAll({
        'title': st(row['name']),
        'artist': sl(row['artists'] ?? row['ar'])
            .map((x) => st(sm(x)['name']))
            .join('、'),
        'album': st(al['name']),
      });
      albumId = st(al['id']);
      cover = st(al['picUrl']);
      try {
        final a = await http.json(
          Uri.https('music.163.com', '/api/album/$albumId'),
          c,
        );
        final album = sm(a['album']);
        if (a['code'] != 200 || album.isEmpty) {
          throw const FormatException('专辑接口没有返回有效信息');
        }
        fields.addAll(songMetadataValues(date: album['publishTime']));
        fields.addAll(
          shareAlbum(
            sl(album['songs'] ?? a['songs']).map(sm).toList(),
            id,
            sn(album['size']),
          ),
        );
      } catch (e) {
        warnings.add('专辑信息不完整');
      }
    } else if (platform == 'qq') {
      id =
          q['songmid'] ??
          q['songid'] ??
          RegExp(r'/songDetail/([a-zA-Z0-9]+)').firstMatch(u.path)?[1] ??
          '';
      if (id.isEmpty) throw const FormatException('未确认QQ歌曲ID');
      final d = await http.json(
        Uri.https('c.y.qq.com', '/v8/fcg-bin/fcg_play_single_song.fcg', {
          RegExp(r'^\d+$').hasMatch(id) ? 'songid' : 'songmid': id,
          'format': 'json',
        }),
        c,
      );
      final row = sl(d['data'])
          .map(sm)
          .where((x) => st(x['mid']) == id || st(x['id']) == id)
          .firstOrNull;
      if (row == null) throw const FormatException('QQ歌曲身份不匹配');
      id = st(row['mid']);
      final al = sm(row['album']);
      albumId = st(al['mid']);
      fields.addAll({
        'title': st(row['name']),
        'artist': sl(row['singer']).map((x) => st(sm(x)['name'])).join('、'),
        'album': st(al['name']),
      });
      fields.addAll(songMetadataValues(date: row['time_public']));
      cover = 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumId.jpg';
      try {
        final a = await http.json(
          Uri.https('u.y.qq.com', '/cgi-bin/musicu.fcg'),
          c,
          post: {
            'comm': {'ct': 24, 'cv': 0},
            'album': {
              'module': 'music.musichallAlbum.AlbumSongList',
              'method': 'GetAlbumSongList',
              'param': {
                'albumMid': albumId,
                'begin': 0,
                'num': 100,
                'order': 2,
              },
            },
          },
        );
        final data = sm(sm(a['album'])['data']);
        fields.addAll(
          shareAlbum(
            sl(data['songList'])
                .map(
                  (x) => {
                    ...sm(sm(x)['songInfo']),
                    'id': sm(sm(x)['songInfo'])['mid'],
                  },
                )
                .toList(),
            id,
            sn(data['totalNum']),
          ),
        );
      } catch (e) {
        warnings.add('专辑信息不完整');
      }
    } else if (platform == 'kuwo' || platform == 'bodian') {
      final mv = q['mvId'];
      id =
          mv ??
          q['musicId'] ??
          RegExp(r'/(?:yinyue|play_detail)/(\d+)').firstMatch(u.path)?[1] ??
          '';
      if (!RegExp(r'^\d+$').hasMatch(id)) {
        throw const FormatException('未确认酷我／波点ID');
      }
      final d = await http.json(
        Uri.https(
          'bd-api.kuwo.cn',
          mv == null ? '/api/service/music/info' : '/api/service/mv/info',
          {
            'musicId': id,
            'uid': '-1',
            'token': '',
            if (mv != null) ...{'wifi': '1', 'noWifi': '1'},
          },
        ),
        c,
        headers: {
          'User-Agent': 'Dart/2.18 (dart:io)',
          'plat': 'ar',
          'ver': '3.1.0',
          'channel': 'aliopen',
          'devId': '0a1b2c3d4e5f6a7b',
        },
      );
      if (d['code'] != 200) {
        throw FormatException(
          st(d['msg']).isEmpty ? '平台未返回有效信息' : st(d['msg']),
        );
      }
      final data = sm(d['data']);
      final row = mv == null ? data : sm(data['mv']);
      if (mv != null && st(row['mid'] ?? row['id']) != id) {
        throw const FormatException('MV身份不匹配');
      }
      if (mv == null && st(row['id']) != id) {
        throw const FormatException('歌曲身份不匹配');
      }
      basic(row, pic: mv == null ? 'albumPic' : 'pic');
      albumId = st(row['albumId']);
      if (mv != null) {
        cover = st(
          row['coverUrl'] ?? row['pic'] ?? row['picUrl'] ?? row['cover'],
        );
        warnings.add('MV视频信息，封面可能为非方形');
      } else {
        try {
          final a = await http.json(
            Uri.http('search.kuwo.cn', '/r.s', {
              'pn': '0',
              'rn': '100',
              'stype': 'albuminfo',
              'albumid': albumId,
              'sortby': '0',
              'alflac': '1',
              'encoding': 'utf8',
              'pcmp4': '1',
              'show_copyright_off': '1',
            }),
            c,
          );
          fields.addAll(
            shareAlbum(
              sl(a['musiclist'])
                  .map(
                    (x) => {
                      ...sm(x),
                      'id': st(sm(x)['id'] ?? sm(x)['musicrid'])
                          .replaceFirst('MUSIC_', ''),
                    },
                  )
                  .toList(),
              id,
              sn(a['songnum']),
            ),
          );
        } catch (e) {
          warnings.add('专辑信息不完整');
        }
      }
    } else if (platform == 'kugou') {
      if (html.isEmpty) html = await http.text(u, c);
      Map<String, dynamic> row = {};
      try {
        row = sm(
          sm(
            sm(looseJson(assignedObject(html, 'phpParam')))['song_info'],
          )['data'],
        );
      } catch (_) {}
      if (row.isEmpty) {
        try {
          final data = sm(looseJson(assignedObject(html, 'dataFromSmarty')));
          row = {
            ...data,
            'songName': data['song_name'],
            'albumid': data['album_id'],
            'album_audio_id': data['mixsongid'],
          };
        } catch (_) {}
      }
      final hash = st(row['hash']).isNotEmpty
          ? st(row['hash'])
          : q['hash'] ??
                RegExp(r'hash=([a-fA-F0-9]{32})')
                    .firstMatch(u.toString())?[1] ??
                '';
      if ((row.isEmpty || st(row['album_img']).isEmpty) && hash.isNotEmpty) {
        try {
          final native = await http.json(
            Uri.http('m.kugou.com', '/app/i/getSongInfo.php', {
              'cmd': 'playInfo',
              'hash': hash,
            }),
            c,
          );
          final targetAlbum = st(row['albumid']);
          final nativeAlbum = st(native['albumid'] ?? native['album_id']);
          if (row.isEmpty ||
              targetAlbum.isNotEmpty && nativeAlbum == targetAlbum) {
            for (final entry in native.entries) {
              if (st(row[entry.key]).isEmpty) row[entry.key] = entry.value;
            }
          }
        } catch (_) {
          warnings.add('部分酷狗元数据未能补全');
        }
      }
      if (row.isEmpty) throw const FormatException('未取得酷狗歌曲信息');
      id = st(row['audio_id']);
      if (id.isEmpty) id = hash;
      basic(
        row,
        title: 'songName',
        artist: 'author_name',
        album: 'album_name',
        pic: 'album_img',
      );
      final authors = sl(row['authors'])
          .map((x) => st(sm(x)['author_name']))
          .where((x) => x.isNotEmpty)
          .toList();
      if (authors.isNotEmpty) fields['artist'] = authors.join('、');
      albumId = st(row['albumid'] ?? row['album_id']);
      try {
        final a = await http.json(
          Uri.http('mobilecdn.kugou.com', '/api/v3/album/info', {
            'albumid': albumId,
            'version': '9108',
            'area_code': '1',
          }),
          c,
        );
        final al = sm(a['data']);
        if (st(al['albumname']).isNotEmpty) {
          fields['album'] = st(al['albumname']);
        }
        fields.addAll(songMetadataValues(date: al['publishtime']));
        final list = await http.json(
          Uri.http('mobilecdn.kugou.com', '/api/v3/album/song', {
            'albumid': albumId,
            'page': '1',
            'pagesize': '300',
            'version': '9108',
            'area_code': '1',
          }),
          c,
        );
        final data = sm(list['data']);
        final rows = sl(data['info']).map((v) {
          final x = sm(v);
          return {
            ...x,
            'id': st(x['audio_id']).isEmpty ? st(x['hash']) : st(x['audio_id']),
          };
        }).toList();
        fields.addAll(shareAlbum(rows, id, sn(data['total'])));
      } catch (e) {
        warnings.add('专辑信息不完整');
      }
    } else if (platform == 'soda') {
      id = q['track_id'] ?? '';
      if (id.isEmpty) throw const FormatException('未确认汽水歌曲ID');
      if (html.isEmpty) {
        html = await http.text(
          Uri.https('music.douyin.com', '/qishui/share/track', {
            'track_id': id,
          }),
          c,
        );
      }
      final router = sm(looseJson(assignedObject(html, '_ROUTER_DATA')));
      final page = sm(sm(router['loaderData'])['track_page']);
      final row = sm(
        page['trackInfo'] ?? sm(page['audioWithLyricsOption'])['trackInfo'],
      );
      if (st(row['id']) != id) throw const FormatException('汽水歌曲身份不匹配');
      final al = sm(row['album']);
      fields.addAll({
        'title': st(row['name']),
        'artist': sl(row['artists']).map((x) => st(sm(x)['name'])).join('、'),
        'album': st(al['name']),
      });
      albumId = st(al['id']);
      fields.addAll(
        songMetadataValues(
          date: sn(al['release_date']) > 0
              ? sn(al['release_date']) * 1000
              : null,
        ),
      );
      final pic = sm(al['url_cover']);
      cover = sl(pic['urls']).isNotEmpty
          ? '${sl(pic['urls']).first}${st(pic['uri'])}~c5_500x500.jpg'
          : '';
      try {
        final text = await http.text(
          Uri.https('www.qishui.com', '/share/album', {'album_id': albumId}),
          c,
        );
        final page = sm(
          sm(
            sm(looseJson(assignedObject(text, '_ROUTER_DATA')))['loaderData'],
          )['album_page'],
        );
        final album = sm(page['albumInfo']);
        if (st(album['id']) != albumId) throw const FormatException('专辑身份不匹配');
        fields.addAll(
          shareAlbum(
            sl(page['trackList']).map(sm).toList(),
            id,
            sn(album['count_tracks']),
          ),
        );
      } catch (e) {
        warnings.add('专辑信息不完整');
      }
    }
    c.check();
    if ((fields['title'] ?? '').isEmpty) {
      throw const FormatException('未取得可靠的歌曲标题');
    }
    warnings.add('曲序若来自完整专辑列表，为列表排序推断；未知碟号不假设为1');
    final song = CoverCandidate(
      source: platform,
      id: id.isEmpty ? u.toString() : id,
      title: fields['title'] ?? '',
      artist: fields['artist'] ?? '',
      album: fields['album'] ?? '',
      artwork: cover,
      albumId: albumId,
      score: 100,
      displaySource: '$platform 分享链接',
    );
    return ShareResult(SongCandidate(song, fields), cover, platform, warnings);
  }
}

List<Uri> shareCoverUrls(String raw, int size) {
  raw = raw.replaceFirst('http://', 'https://');
  final u = Uri.parse(raw);
  final sizes = size == 0
      ? [0, 1000, 500, 300, 150]
      : [size, if (size > 500) 500, if (size > 300) 300, 150];
  return sizes
      .toSet()
      .map((n) {
        var text = raw;
        if (u.host.endsWith('music.126.net')) {
          return u.replace(
            queryParameters: {
              ...u.queryParameters,
              if (n > 0) 'param': '${n}y$n',
            },
          );
        }
        if (u.host.endsWith('gtimg.cn')) {
          text = text.replaceFirst(
            RegExp(r'T002R\d+x\d+M000'),
            'T002R${n == 0 ? 1000 : n}x${n == 0 ? 1000 : n}M000',
          );
        } else if (text.contains('{size}')) {
          text = text.replaceAll('{size}', '${n == 0 ? 1000 : n}');
        } else if (u.host.endsWith('kuwo.cn')) {
          text = text.replaceFirst(
            RegExp(r'/(?:800|700|500|300|150)/'),
            '/${n == 0 ? 1000 : n}/',
          );
        } else if (u.host.endsWith('douyinpic.com')) {
          text = text.replaceFirst(
            RegExp(r'~c5_\d+x\d+'),
            n == 0 ? '' : '~c5_${n}x$n',
          );
        }
        return Uri.parse(text);
      })
      .toSet()
      .toList();
}

class ShareCoverClient extends CoverSearchClient {
  final shared = ShareHttp();
  @override
  void close() {
    shared.close();
    super.close();
  }

  @override
  Future<Uint8List> artwork(
    CoverCandidate c,
    int size,
    CoverCancel cancel, {
    void Function(int, int)? progress,
  }) async {
    Object? last;
    for (final u in shareCoverUrls(c.artwork, size)) {
      try {
        final bytes =
            (await shared.read(u, cancel).timeout(const Duration(seconds: 30)))
                .$1;
        if (!imageSignature(bytes)) throw const FormatException('不是图片');
        return bytes;
      } on CoverCancelled {
        rethrow;
      } catch (e) {
        last = e;
      }
    }
    throw FormatException('封面加载失败：${conciseError(last)}');
  }
}
