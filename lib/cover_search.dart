import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

class CoverCancelled implements Exception {
  const CoverCancelled();
}

class CoverCancel {
  bool cancelled = false;
  final Set<HttpClientRequest> _requests = {};
  void check() {
    if (cancelled) throw const CoverCancelled();
  }

  void cancel() {
    cancelled = true;
    for (final r in _requests.toList()) {
      r.abort(const CoverCancelled());
    }
  }

  Future<void> delay(Duration duration) async {
    final until = DateTime.now().add(duration);
    while (DateTime.now().isBefore(until)) {
      check();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    check();
  }
}

class CoverCandidate {
  final String source, id, title, artist, album, artwork, albumId;
  final String displaySource;
  String get sourceName => displaySource.isEmpty
      ? (CoverSearchClient.sources[source] ?? source)
      : displaySource;
  final List<String> aliases;
  final Map<String, String> metadata;
  final int duration;
  final double score;
  const CoverCandidate({
    this.displaySource = '',
    this.metadata = const {},
    required this.source,
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.artwork,
    this.albumId = '',
    this.duration = 0,
    this.aliases = const [],
    this.score = 0,
  });
  CoverCandidate scored(double value) => CoverCandidate(
    source: source,
    displaySource: displaySource,
    id: id,
    title: title,
    artist: artist,
    album: album,
    artwork: artwork,
    albumId: albumId,
    duration: duration,
    aliases: aliases,
    metadata: metadata,
    score: value,
  );
}

String matchNormalize(String value) => unorm
    .nfd(unorm.nfkc(value))
    .toLowerCase()
    .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
    .replaceAll(RegExp(r'[\[\](){}（）【】「」『』]'), ' ')
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
double textSimilarity(String a, String b) {
  a = matchNormalize(a);
  b = matchNormalize(b);
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1;
  if (a.contains(b) || b.contains(a)) {
    final short = math.min(a.length, b.length),
        ratio = short / math.max(a.length, b.length);
    if (short <= 2) return ratio * .7;
    if (short == 3) return math.max(.35, ratio * .8);
    if (ratio >= .8) return .94;
    if (ratio >= .65) return .85;
    if (ratio >= .5) return .72;
    return math.max(.35, ratio);
  }
  // Bound edit-distance work for malformed/very long remote metadata.
  final ar = a.runes.take(256).toList(), br = b.runes.take(256).toList();
  var row = List.generate(br.length + 1, (i) => i);
  for (var i = 1; i <= ar.length; i++) {
    final next = List.filled(br.length + 1, 0);
    next[0] = i;
    for (var j = 1; j <= br.length; j++) {
      next[j] = math.min(
        math.min(next[j - 1] + 1, row[j] + 1),
        row[j - 1] + (ar[i - 1] == br[j - 1] ? 0 : 1),
      );
    }
    row = next;
  }
  final lev = 1 - row.last / math.max(ar.length, br.length);
  final x = a.split(' ').toSet(), y = b.split(' ').toSet();
  return math.max(lev, 2 * x.intersection(y).length / (x.length + y.length));
}

String cleanFeaturing(String s) => s
    .replaceFirst(
      RegExp(
        r'\s*(?:\(?\b(?:feat\.?|ft\.?|featuring)\b).*$',
        caseSensitive: false,
      ),
      '',
    )
    .trim();
List<String> _artists(String s) => s
    .split(
      RegExp(
        r'\s*(?:/|、|，|,|;|；|&|＋|\+|\bfeat\.?\b|\bfeaturing\b)\s*',
        caseSensitive: false,
      ),
    )
    .where((x) => x.trim().isNotEmpty)
    .toList();
double artistSimilarity(String a, String b) {
  final x = _artists(a), y = _artists(b);
  if (x.isEmpty || y.isEmpty) return 0;
  final mean =
      x
          .map((v) => y.map((w) => textSimilarity(v, w)).reduce(math.max))
          .reduce((a, b) => a + b) /
      x.length;
  return math.max(
    mean,
    textSimilarity((x..sort()).join(' '), (y..sort()).join(' ')),
  );
}

double matchScore(
  CoverCandidate c,
  String title,
  String artist,
  String album, {
  int duration = 0,
}) {
  var t = math.max(
    textSimilarity(title, c.title),
    textSimilarity(cleanFeaturing(title), cleanFeaturing(c.title)),
  );
  for (final a in c.aliases) {
    t = math.max(t, textSimilarity(title, a));
  }
  final a = artistSimilarity(artist, c.artist),
      b = textSimilarity(album, c.album);
  final hasA = artist.trim().isNotEmpty,
      hasB =
          album.trim().isNotEmpty &&
          !['unknown', '未知专辑'].contains(matchNormalize(album));
  final hasD = duration > 0 && c.duration > 0;
  final diff = (duration - c.duration).abs() / 1000;
  final d = diff <= 2
      ? 1.0
      : diff <= 5
      ? .92
      : diff <= 10
      ? .75
      : diff <= 20
      ? .45
      : diff <= 40
      ? .15
      : 0.0;
  double wt = 40, wa = hasA ? 40 : 0, wb = hasB ? 15 : 0, wd = hasD ? 5 : 0;
  if (!hasA && hasB) {
    wt = 65;
    wb = 25;
    wd = hasD ? 10 : 0;
  } else if (hasA && !hasB) {
    wt = 45;
    wa = 45;
    wd = hasD ? 10 : 0;
  } else if (!hasA && !hasB) {
    wt = 90;
    wd = hasD ? 10 : 0;
  }
  var score = (t * wt + a * wa + b * wb + d * wd) / (wt + wa + wb + wd) * 100;
  final titleVsAlbum = textSimilarity(title, c.album),
      albumVsTitle = textSimilarity(album, c.title);
  if (t < .55 && titleVsAlbum >= .88 && titleVsAlbum - t >= .25) {
    score = math.min(score, 8);
  }
  if (hasB && b < .45 && albumVsTitle >= .9 && t < .75) {
    score = math.min(score, 10);
  }
  if (t < .35) score = math.min(score, 20);
  if (hasA && a < .25 && t < .92) score = math.min(score, 25);
  if (hasB && b < .25) score = math.min(score, 30);
  if (t < .55) {
    score = math.min(score, 49);
  } else if (t < .7) {
    score = math.min(score, 69);
  }
  if (hasA && a < .45) {
    score = math.min(score, 54);
  } else if (hasA && a < .65) {
    score = math.min(score, 74);
  }
  if (hasB && b < .45) {
    score = math.min(score, 54);
  } else if (hasB && b < .65) {
    score = math.min(score, 74);
  }
  if (t >= .995 && (!hasA || a >= .95)) {
    score += 4;
  } else if (t >= .93 && (!hasA || a >= .9)) {
    score += 2;
  }
  if (hasB && b >= .995) score += 1.5;
  for (final marker in [
    'live',
    '现场',
    'concert',
    'remix',
    'acoustic',
    '不插电',
    'instrumental',
    '伴奏',
    'karaoke',
    'demo',
    'cover',
    '翻唱',
    'radio edit',
  ]) {
    if (matchNormalize(title).contains(marker) !=
        matchNormalize(c.title).contains(marker)) {
      score -= 10;
      break;
    }
  }
  if (hasB && b < .35) score -= 4;
  if (hasD && d <= .15) score -= 5;
  return score.clamp(0, 100);
}

/// All endpoints use a single bounded connection pool. No WebView or server is needed.
class CoverHttp {
  final HttpClient client;
  CoverHttp({HttpClient? client}) : client = client ?? HttpClient() {
    this.client.connectionTimeout = const Duration(seconds: 12);
    this.client.idleTimeout = const Duration(seconds: 15);
    this.client.maxConnectionsPerHost = 3;
    this.client.userAgent = 'Mozilla/5.0 MusicCardX/1.4.2';
  }
  void close() => client.close(force: true);
  Future<Uint8List> read(
    Uri uri,
    CoverCancel cancel, {
    Map<String, String> headers = const {},
    Map<String, String>? form,
    int maxBytes = 8 * 1024 * 1024,
    void Function(int, int)? progress,
  }) async {
    cancel.check();
    if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' &&
            InternetAddress.tryParse(uri.host)?.isLoopback == true)) {
      throw const FormatException('仅支持HTTPS');
    }
    HttpClientRequest? request;
    final timer = Timer(
      const Duration(seconds: 30),
      () => request?.abort(const HttpException('请求超时')),
    );
    try {
      request = await client.openUrl(form == null ? 'GET' : 'POST', uri);
      cancel.check();
      cancel._requests.add(request);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json,image/*,*/*',
      );
      for (final e in headers.entries) {
        request.headers.set(e.key, e.value);
      }
      if (form != null) {
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );
        request.write(
          form.entries
              .map(
                (e) =>
                    '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
              )
              .join('&'),
        );
      }
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      if (response.contentLength > maxBytes) {
        throw const FormatException('响应内容过大');
      }
      final bytes = BytesBuilder(copy: false);
      var total = 0;
      await for (final b in response) {
        cancel.check();
        total += b.length;
        if (total > maxBytes) throw const FormatException('响应内容过大');
        bytes.add(b);
        progress?.call(total, response.contentLength);
      }
      cancel.check();
      return bytes.takeBytes();
    } finally {
      timer.cancel();
      if (request != null) {
        cancel._requests.remove(request);
        request.abort();
      }
    }
  }

  Future<Map<String, dynamic>> json(
    Uri uri,
    CoverCancel cancel, {
    Map<String, String> headers = const {},
    Map<String, String>? form,
  }) async {
    final data = jsonDecode(
      utf8
          .decode(await read(uri, cancel, headers: headers, form: form))
          .replaceFirst('\uFEFF', ''),
    );
    if (data is! Map<String, dynamic>) {
      throw const FormatException('接口未返回JSON对象');
    }
    return data;
  }
}

class NeteaseCipher {
  static Uint8List _aes(String text, String key, {bool cbc = false}) {
    final cipher = PaddedBlockCipher(cbc ? 'AES/CBC/PKCS7' : 'AES/ECB/PKCS7');
    final k = KeyParameter(Uint8List.fromList(utf8.encode(key)));
    cipher.init(
      true,
      PaddedBlockCipherParameters(
        cbc
            ? ParametersWithIV(
                k,
                Uint8List.fromList(utf8.encode('0102030405060708')),
              )
            : k,
        null,
      ),
    );
    return cipher.process(Uint8List.fromList(utf8.encode(text)));
  }

  static Map<String, String> eapi(Map<String, dynamic> data) {
    const path = '/api/cloudsearch/pc';
    final json = jsonEncode(data);
    final hash = md5.convert(
      utf8.encode('nobody${path}use${json}md5forencrypt'),
    );
    final b = _aes(
      '$path-36cd479b6b5-$json-36cd479b6b5-$hash',
      'e82ckenh8dichen8',
    );
    return {
      'params': b
          .map((v) => v.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase(),
    };
  }

  static Map<String, String> weapi(Map<String, String> data, {String? secret}) {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = math.Random.secure();
    final key =
        secret ??
        List.generate(
          16,
          (_) => alphabet[random.nextInt(alphabet.length)],
        ).join();
    final first = base64Encode(
      _aes(jsonEncode(data), '0CoJUm6Qyw8W8jud', cbc: true),
    );
    final second = base64Encode(_aes(first, key, cbc: true));
    final reversed = utf8
        .encode(key.split('').reversed.join())
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
    final modulus = BigInt.parse(
      'e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7',
      radix: 16,
    );
    return {
      'params': second,
      'encSecKey': BigInt.parse(
        reversed,
        radix: 16,
      ).modPow(BigInt.from(65537), modulus).toRadixString(16).padLeft(256, '0'),
    };
  }
}

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : {};
List<dynamic> _list(dynamic v) => v is List ? v : [];
int _int(dynamic v) => int.tryParse('$v') ?? 0;
String _text(dynamic v) => v == null ? '' : '$v';

class CoverSearchClient {
  final CoverHttp http;
  static DateTime _nextApple = DateTime.fromMillisecondsSinceEpoch(0);
  String? _token;
  DateTime _tokenUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _preferEapi = false;
  final bool metadataOnly;
  CoverSearchClient({CoverHttp? http, this.metadataOnly = false})
    : http = http ?? CoverHttp();
  void close() => http.close();
  static const sources = {
    '163': '163',
    'apple': 'Apple',
    'appleweb': 'Apple不限速',
  };
  static List<CoverCandidate> parse(
    String source,
    Map<String, dynamic> root, {
    String variant = '',
    bool requireArtwork = true,
  }) {
    final result = <CoverCandidate>[];
    final songs = source == '163'
        ? _list(_map(root['result'])['songs'])
        : source == 'apple'
        ? _list(root['results'])
        : _list(_map(_map(root['results'])['songs'])['data']);
    if (source == '163' && root['code'] != null && root['code'] != 200) {
      throw FormatException('163返回${root['code']}');
    }
    for (final raw in songs) {
      final row = _map(raw);
      String id, title, artist, album, artwork, albumId;
      int duration;
      Map<String, String> metadata = {};
      List<String> aliases = [];
      if (source == '163') {
        final al = _map(row['album'] ?? row['al']);
        id = _text(row['id']);
        title = _text(row['name']);
        artist = _list(row['artists'] ?? row['ar'])
            .map((v) => _text(_map(v)['name']))
            .join(' / ');
        album = _text(al['name']);
        artwork = _text(al['picUrl'] ?? al['blurPicUrl']);
        albumId = _text(al['id']);
        duration = _int(row['duration'] ?? row['dt']);
        aliases = _list(row['alias'] ?? row['alia']).map(_text).toList();
        metadata = songMetadataValues(
          date: al['publishTime'] ?? row['publishTime'],
          disc: row['disc'] ?? row['cd'],
          track: row['no'],
        );
      } else if (source == 'apple') {
        if (row['wrapperType'] != 'track' || row['kind'] != 'song') continue;
        id = _text(row['trackId']);
        title = _text(row['trackName']);
        artist = _text(row['artistName']);
        album = _text(row['collectionName']);
        artwork = _text(row['artworkUrl100'] ?? row['artworkUrl60']);
        albumId = _text(row['collectionId']);
        duration = _int(row['trackTimeMillis']);
        metadata = songMetadataValues(
          date: row['releaseDate'],
          disc: row['discNumber'],
          discs: row['discCount'],
          track: row['trackNumber'],
          tracks: row['trackCount'],
        );
      } else {
        final a = _map(row['attributes']);
        id = _text(row['id']);
        title = _text(a['name']);
        artist = _text(a['artistName']);
        album = _text(a['albumName']);
        artwork = _text(_map(a['artwork'])['url']);
        albumId = _text(
          _map(
            _list(_map(_map(row['relationships'])['albums'])['data'])
                .firstOrNull,
          )['id'],
        );
        duration = _int(a['durationInMillis']);
        metadata = songMetadataValues(
          date: a['releaseDate'],
          disc: a['discNumber'],
          discs: a['discCount'],
          track: a['trackNumber'],
          tracks: a['trackCount'],
        );
      }
      if (title.isEmpty) continue;
      if (requireArtwork && source != '163' && !isAppleArtwork(artwork)) {
        continue;
      }
      result.add(
        CoverCandidate(
          source: source,
          displaySource: variant,
          id: id,
          title: title,
          artist: artist,
          album: album,
          artwork: artwork.replaceFirst('http://', 'https://'),
          albumId: albumId,
          duration: duration,
          aliases: aliases,
          metadata: metadata,
        ),
      );
    }
    return result;
  }

  static bool isAppleArtwork(String s) {
    final u = Uri.tryParse(s.replaceAll('{w}', '100').replaceAll('{h}', '100'));
    return u != null &&
        u.host.endsWith('.mzstatic.com') &&
        RegExp(r'/Music\d*(?:/|$)', caseSensitive: false).hasMatch(u.path);
  }

  Future<List<CoverCandidate>> searchSource(
    String source,
    String query,
    String region,
    CoverCancel cancel,
  ) async {
    if (source == '163') {
      Object? last;
      var success = false;
      for (final route
          in _preferEapi
              ? ['eapi', 'legacy', 'weapi']
              : ['legacy', 'eapi', 'weapi']) {
        try {
          Map<String, dynamic> json;
          if (route == 'legacy') {
            json = await http.json(
              Uri.https('music.163.com', '/api/search/get/web', {
                's': query,
                'type': '1',
                'limit': '30',
                'offset': '0',
              }),
              cancel,
              headers: {'Referer': 'https://music.163.com/'},
            );
          } else {
            final data = {
              's': query,
              'type': '1',
              'limit': '30',
              'offset': '0',
              'total': 'true',
              'csrf_token': '',
            };
            final now = DateTime.now().millisecondsSinceEpoch;
            final header = {
              'os': 'android',
              'appver': '8.0.0',
              'versioncode': '140',
              '__csrf': '',
              'deviceId': '',
              'MUSIC_U': '',
              'buildver': '${now ~/ 1000}',
              'requestId': '${now}_${math.Random().nextInt(10000)}',
            };
            json = await http.json(
              Uri.parse(
                route == 'eapi'
                    ? 'https://interface.music.163.com/eapi/cloudsearch/pc'
                    : 'https://music.163.com/weapi/search/get',
              ),
              cancel,
              form: route == 'eapi'
                  ? NeteaseCipher.eapi({...data, 'header': jsonEncode(header)})
                  : NeteaseCipher.weapi(data),
              headers: {
                'Referer': 'https://music.163.com/',
                if (route == 'eapi')
                  'Cookie': header.entries
                      .map((e) => '${e.key}=${e.value}')
                      .join('; '),
              },
            );
          }
          final rows = parse(
            source,
            json,
            requireArtwork: !metadataOnly,
            variant:
                '163 ${route == 'legacy' ? 'Legacy' : route.toUpperCase()}',
          );
          success = true;
          if (rows.isNotEmpty) {
            _preferEapi = route == 'eapi';
            return rows;
          }
        } on CoverCancelled {
          rethrow;
        } catch (e) {
          cancel.check();
          last = e;
        }
      }
      if (!success) throw Exception('163搜索失败：$last');
      return [];
    }
    if (source == 'apple') {
      final now = DateTime.now();
      final slot = _nextApple.isAfter(now) ? _nextApple : now;
      _nextApple = slot.add(const Duration(milliseconds: 3100));
      final wait = slot.difference(now);
      if (!wait.isNegative) await cancel.delay(wait);
      final json = await http.json(
        Uri.https('itunes.apple.com', '/search', {
          'term': query,
          'country': region,
          'media': 'music',
          'entity': 'song',
          'limit': '30',
          'explicit': 'Yes',
        }),
        cancel,
      );
      return parse(
        source,
        json,
        variant: 'Apple ${region.toUpperCase()}',
        requireArtwork: !metadataOnly,
      );
    }
    final token = await _appleToken(region, cancel);
    try {
      final root = await http.json(
        Uri.https('amp-api.music.apple.com', '/v1/catalog/$region/search', {
          'term': query,
          'types': 'songs',
          'include[songs]': 'albums',
          'limit': '25',
          'l': region == 'cn' ? 'zh-Hans-CN' : 'en-US',
        }),
        cancel,
        headers: {
          'Authorization': 'Bearer $token',
          'Origin': 'https://music.apple.com',
          'Referer': 'https://music.apple.com/',
        },
      );
      return parse(
        source,
        root,
        variant: 'Apple不限速 ${region.toUpperCase()}',
        requireArtwork: !metadataOnly,
      );
    } catch (_) {
      _token = null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> appleCatalogAlbum(
    String id,
    String region,
    CoverCancel cancel,
  ) async {
    final token = await _appleToken(region, cancel);
    return http.json(
      Uri.https(
        'amp-api.music.apple.com',
        '/v1/catalog/$region/albums/${Uri.encodeComponent(id)}',
        {'include': 'tracks', 'limit[tracks]': '100'},
      ),
      cancel,
      headers: {
        'Authorization': 'Bearer $token',
        'Origin': 'https://music.apple.com',
        'Referer': 'https://music.apple.com/',
      },
    );
  }

  Future<String> _appleToken(String region, CoverCancel cancel) async {
    if (_token != null && DateTime.now().isBefore(_tokenUntil)) return _token!;
    final page = Uri.parse('https://music.apple.com/$region/new');
    final html = utf8.decode(await http.read(page, cancel));
    final jwt = RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+');
    String? token = jwt.firstMatch(html)?.group(0);
    if (token == null) {
      final scripts =
          RegExp(r'''<script[^>]+src=["']([^"']+)["']''', caseSensitive: false)
              .allMatches(html)
              .map((m) => page.resolve(m.group(1)!.replaceAll('&amp;', '&')))
              .where((u) => u.scheme == 'https' && u.host == 'music.apple.com')
              .toSet()
              .toList();
      scripts.sort(
        (a, b) => (b.path.contains('index') ? 1 : 0).compareTo(
          a.path.contains('index') ? 1 : 0,
        ),
      );
      for (final script in scripts.take(14)) {
        try {
          token = jwt
              .firstMatch(utf8.decode(await http.read(script, cancel)))
              ?.group(0);
          if (token != null) break;
        } on CoverCancelled {
          rethrow;
        } catch (_) {
          cancel.check();
        }
      }
    }
    if (token == null) throw const FormatException('Apple网页令牌读取失败');
    _token = token;
    _tokenUntil = DateTime.now().add(const Duration(minutes: 20));
    return token;
  }

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
    if (title.trim().isEmpty && artist.trim().isEmpty && album.trim().isEmpty) {
      throw const FormatException('请填写搜索信息');
    }
    if (enabled.isEmpty) throw const FormatException('请选择搜索源');
    final queries = [
      [title, artist, album].where((s) => s.trim().isNotEmpty).join(' '),
      [
        cleanFeaturing(title),
        artist,
      ].where((s) => s.trim().isNotEmpty).join(' '),
      cleanFeaturing(title),
    ].where((s) => s.isNotEmpty).toSet();
    final all = <String, CoverCandidate>{}, status = <String, String>{};
    var succeeded = false;
    var round = 0;
    List<CoverCandidate> sorted() {
      final list =
          all.values
              .map(
                (c) => c.scored(
                  matchScore(c, title, artist, album, duration: duration),
                ),
              )
              .toList()
            ..sort((a, b) => b.score.compareTo(a.score));
      // One entry per provider/album/artwork; retain the best matching track.
      final seen = <String>{};
      return list
          .where(
            (c) => seen.add(
              '${c.source}:${c.albumId.isEmpty ? c.artwork : c.albumId}:${c.album}',
            ),
          )
          .take(60)
          .toList();
    }

    for (final q in queries) {
      cancel.check();
      for (final source in enabled) {
        status[source] = '搜索中';
      }
      onUpdate(sorted(), Map.of(status));
      await Future.wait(
        enabled.map((source) async {
          try {
            final rows = await searchSource(source, q, region, cancel);
            cancel.check();
            succeeded = true;
            for (final c in rows) {
              all['$source:${c.id}'] = c;
            }
            status[source] = '已完成';
          } on CoverCancelled {
            rethrow;
          } catch (e) {
            cancel.check();
            status[source] = '失败：${conciseError(e)}';
          }
          onUpdate(sorted(), Map.of(status));
        }),
      );
      final rows = sorted();
      if (rows.isNotEmpty && rows.first.score >= (round == 0 ? 92 : 78)) break;
      round++;
    }
    cancel.check();
    if (!succeeded) throw const HttpException('所选搜索源均失败');
    return sorted();
  }

  Future<String> _resolveArtwork(CoverCandidate c, CoverCancel cancel) async {
    if (c.artwork.isNotEmpty) return c.artwork;
    if (c.source != '163' || c.albumId.isEmpty) {
      throw const FormatException('候选缺少封面');
    }
    Object? last;
    for (final path in [
      '/api/v1/album/${c.albumId}',
      '/api/album/${c.albumId}',
    ]) {
      try {
        final data = await http.json(Uri.https('music.163.com', path), cancel);
        final url = _text(_map(data['album'])['picUrl']);
        if (url.isNotEmpty) return url.replaceFirst('http://', 'https://');
      } on CoverCancelled {
        rethrow;
      } catch (e) {
        cancel.check();
        last = e;
      }
    }
    throw FormatException('无法取得专辑封面：${last ?? '无封面地址'}');
  }

  static List<Uri> artworkUrls(String url, int size, {required bool apple}) {
    if (size < 0 || size > 10000) throw const FormatException('尺寸范围0—10000');
    final source = Uri.parse(url.replaceFirst('http://', 'https://'));
    if (!apple) {
      return [
        source.replace(
          queryParameters: {
            ...source.queryParameters,
            if (size > 0) 'param': '${size}y$size',
          },
        ),
        if (size > 0) source,
      ];
    }
    if (!isAppleArtwork(url)) throw const FormatException('不是Apple静态音乐封面');
    final sizes = size == 0 ? [4000, 3000, 2000, 1200] : [size];
    final urls = <Uri>[];
    for (final n in sizes) {
      for (final suffix in ['${n}x$n.png', '${n}x${n}bb.jpg', '${n}x$n.jpg']) {
        var path = Uri.decodeComponent(source.path).replaceAll(
          RegExp(
            r'/(?:\{w\}|\d+)x(?:\{h\}|\d+)(?:bb)?(?:-[^./]+)?\.(?:webp|jpe?g|png)$',
            caseSensitive: false,
          ),
          '/$suffix',
        );
        if (path == Uri.decodeComponent(source.path)) {
          path = Uri.decodeComponent(source.path).replaceAll(
            RegExp(
              r'\.(?:\{w\}|\d+)x(?:\{h\}|\d+)(?:bb)?(?:-\d+)?\.(?:webp|jpe?g|png)$',
              caseSensitive: false,
            ),
            '.$suffix',
          );
        }
        urls.add(source.replace(path: path));
      }
    }
    urls.add(source);
    return urls.toSet().toList();
  }

  Future<Uint8List> artwork(
    CoverCandidate c,
    int size,
    CoverCancel cancel, {
    void Function(int, int)? progress,
  }) async {
    final url = await _resolveArtwork(c, cancel);
    Object? last;
    for (final uri in artworkUrls(url, size, apple: c.source != '163')) {
      try {
        final bytes = await http.read(
          uri,
          cancel,
          maxBytes: 32 * 1024 * 1024,
          headers: {
            'Referer': c.source == '163'
                ? 'https://music.163.com/'
                : 'https://music.apple.com/',
          },
          progress: progress,
        );
        if (!imageSignature(bytes)) throw const FormatException('响应不是图片');
        return bytes;
      } on CoverCancelled {
        rethrow;
      } catch (e) {
        cancel.check();
        last = e;
      }
    }
    throw Exception('封面下载失败：${conciseError(last)}');
  }
}

bool imageSignature(Uint8List b) =>
    b.length >= 8 &&
    ((b[0] == 255 && b[1] == 216 && b[2] == 255) ||
        (b[0] == 137 && b[1] == 80 && b[2] == 78 && b[3] == 71) ||
        (b[0] == 71 && b[1] == 73 && b[2] == 70) ||
        (b.length >= 12 &&
            ascii.decode(b.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
            ascii.decode(b.sublist(8, 12), allowInvalid: true) == 'WEBP'));
String conciseError(Object? e) {
  final s = '$e'
      .replaceAll(RegExp(r'https?://\S+'), '')
      .replaceFirst(
        RegExp(r'^(Exception|FormatException|HttpException):\s*'),
        '',
      )
      .trim();
  return s.length > 90 ? '${s.substring(0, 90)}…' : s;
}

/// Never infer a disc count or invent a missing day/month.
Map<String, String> songMetadataValues({
  dynamic date,
  dynamic disc,
  dynamic discs,
  dynamic track,
  dynamic tracks,
}) {
  final out = <String, String>{};
  final raw = '$date';
  if (date is num && date != 0) {
    // Chinese providers publish milliseconds at midnight in UTC+8.
    final d = DateTime.fromMillisecondsSinceEpoch(
      date.toInt(),
      isUtc: true,
    ).add(const Duration(hours: 8));
    if (d.year >= 1900 && d.year < 2200) {
      out['date'] =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
  } else if (RegExp(r'^\d{4}(-\d{2}){0,2}($|T| )').hasMatch(raw)) {
    out['date'] = raw.split(RegExp('[T ]')).first;
  }
  for (final e in {
    'discnumber': disc,
    'totaldiscs': discs,
    'tracknumber': track,
    'totaltracks': tracks,
  }.entries) {
    final n = int.tryParse('${e.value}');
    if (n != null && n > 0) {
      out[e.key] = '$n';
    }
  }
  return out;
}
