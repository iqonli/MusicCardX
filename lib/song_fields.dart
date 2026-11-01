import 'dart:convert';

/// Tags are nonempty strings, finite numbers, or nonempty lists of those values.
/// Booleans, nulls, objects and empty values are removed rather than stringified.
const songInputFields = <String, String>{
  'title': '标题',
  'artist': '艺术家',
  'album artist': '专辑艺术家',
  'album': '专辑',
  'date': '日期／年份',
  'discnumber': 'Disc',
  'totaldiscs': 'Disc总数',
  'tracknumber': 'Track',
  'totaltracks': 'Track总数',
};

Map<String, dynamic> normalizeSongFields(
  Map<String, dynamic> source, {
  Iterable<String> disabled = const [],
}) {
  final out = <String, dynamic>{};
  String? scalar(dynamic v) => v is String
      ? (v.replaceAll('\x00', '').trim().isEmpty
            ? null
            : v.replaceAll('\x00', '').trim())
      : v is num && v.isFinite
      ? '$v'
      : null;
  for (final e in source.entries) {
    final key = e.key.trim().toLowerCase();
    if (disabled.contains(key)) continue;
    if (key.isEmpty || key.contains(RegExp(r'[\x00-\x1f]'))) continue;
    if (key == songCoverLinkField) {
      if (e.value is String) {
        final value = scalar(e.value);
        if (value != null) out[key] = value;
      }
      continue;
    }
    if (e.value is List) {
      final a = (e.value as List).map(scalar).whereType<String>().toList();
      if (a.isNotEmpty) out[key] = a;
    } else {
      final v = scalar(e.value);
      if (v != null) out[key] = v;
    }
  }
  return out;
}

/// Reserved metadata only. Neither local files nor remote URLs are opened here.
const songCoverLinkField = 'cover';
Map<String, dynamic> decodeSongJson(String raw) {
  var text = raw.trim().replaceFirst('\uFEFF', '');
  final fence = RegExp(
    r'^```(?:json)?\s*\n([\s\S]*?)\n```$',
    caseSensitive: false,
  ).firstMatch(text);
  if (fence != null) text = fence[1]!.trim();
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('歌曲信息须为JSON对象');
  }
  return decoded;
}
