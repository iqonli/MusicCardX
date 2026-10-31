import 'model.dart';
import 'song_fields.dart';

/// A configuration import only accepts schema keys with matching value types.
/// Invalid optional values are discarded; CardDocument supplies required defaults.
Map<String, dynamic> normalizeConfiguration(Map<String, dynamic> raw) {
  final schema = CardDocument.fresh().data;
  Map<String, dynamic> clean(Map source, Map template) {
    final out = <String, dynamic>{};
    for (final e in source.entries) {
      if (e.key is! String || !template.containsKey(e.key)) continue;
      final key = e.key as String, v = e.value, expected = template[key];
      if (v == null) continue;
      if (key == 'letterSpacing') {
        final n = v is num
            ? v
            : v is String
            ? num.tryParse(v)
            : null;
        if (v == '') {
          out[key] = '';
        } else if (n != null && n.isFinite) {
          out[key] = n.clamp(-1000, 1000);
        }
        continue;
      }
      if (expected is Map && v is Map) {
        out[key] = clean(v, expected);
      } else if (expected is bool && v is bool) {
        out[key] = v;
      } else if (expected is num) {
        final n = v is num
            ? v
            : v is String
            ? num.tryParse(v)
            : null;
        if (n != null && n.isFinite) out[key] = n;
      } else if (expected is String && v is String) {
        if (key.toLowerCase().contains('hex') && !validColor(v)) continue;
        out[key] = key.toLowerCase().contains('hex') ? v.toLowerCase() : v;
      } else if (expected is List && v is List) {
        if (v.every((a) => a is String)) out[key] = List<String>.from(v);
      }
    }
    return out;
  }

  for (final row in (schema['style'] as Map).values) {
    row['weight'] = 400;
  }
  (schema['lyrics'] as Map)['weight'] = 400;
  schema['previewPinned'] = true;
  final source = Map<String, dynamic>.from(raw);
  final out = clean(source, schema);
  if (source['fields'] is Map) {
    out['fields'] = normalizeSongFields(
      Map<String, dynamic>.from(source['fields']),
    );
  }
  // Empty letter spacing is valid; otherwise it is a finite numeric value.
  for (final entry in [
    ...mapv(out['style']).values,
    if (out['lyrics'] is Map) out['lyrics'],
  ]) {
    if (entry is! Map || !entry.containsKey('letterSpacing')) continue;
    final v = entry['letterSpacing'];
    if (v != '' && double.tryParse('$v') == null) entry.remove('letterSpacing');
  }
  for (final e in {
    'imageFormat': ['png', 'jpg'],
    'backgroundStyle': backgrounds.keys,
    'textOpenCCMode': ccModes.keys,
    'lyricsOpenCCMode': ccModes.keys,
    'textAlignMode': ['top', 'center', 'bottom'],
    'autoColorMode': ['auto', 'black', 'white'],
    'coverShape': [
      'round',
      'continuous',
      'superellipse',
      'bevel',
      'concave',
      'ellipse',
      'individual',
      'elliptical',
      'quadratic',
      'scoop',
    ],
    'paletteAlgorithm': ['celebi', 'wu', 'histogram', 'foobar'],
    'irregularCoverMode': ['crop', 'tile'],
    'rainbowMode': ['auto', 'custom'],
  }.entries) {
    if (out.containsKey(e.key) && !e.value.contains(out[e.key])) {
      out.remove(e.key);
    }
  }
  // Legacy values are intentionally passed to CardDocument's migrations.
  for (final key in ['textOpenCCMode', 'lyricsOpenCCMode']) {
    if (raw[key] == 's2tw') out[key] = 's2tw';
  }
  if (raw['coverShapeParameters'] is Map) {
    out['coverShapeParameters'] = <String, dynamic>{};
    for (final e in (raw['coverShapeParameters'] as Map).entries) {
      if (![
            'round',
            'continuous',
            'superellipse',
            'bevel',
            'concave',
            'ellipse',
            'individual',
            'elliptical',
            'quadratic',
            'scoop',
          ].contains(e.key) ||
          e.value is! Map) {
        continue;
      }
      (out['coverShapeParameters'] as Map)[e.key] = clean(e.value, {
        'coverCornerRadius': 0,
        'coverExponent': 4,
        'cornerRadiusX': 40,
        'cornerRadiusY': 20,
        'cornerTension': 0,
        'cornerTL': 0,
        'cornerTR': 0,
        'cornerBL': 0,
        'cornerBR': 0,
      });
    }
  }
  if (out['coverSearchMinScore'] is num) {
    out['coverSearchMinScore'] = (out['coverSearchMinScore'] as num).clamp(
      0,
      100,
    );
  }
  for (final key in ['coverSearchPreviewSize', 'coverSearchDownloadSize']) {
    if (out.containsKey(key)) {
      out[key] = (out[key] as num).round().clamp(0, 10000);
    }
  }
  if (out.containsKey('coverSearchRegion')) {
    final region = '${out['coverSearchRegion']}'.toLowerCase();
    if (RegExp(r'^[a-z]{2}$').hasMatch(region)) {
      out['coverSearchRegion'] = region;
    } else {
      out.remove('coverSearchRegion');
    }
  }
  if (out.containsKey('songSearchRegion')) {
    final region = '${out['songSearchRegion']}'.toLowerCase();
    if (RegExp(r'^[a-z]{2}$').hasMatch(region)) {
      out['songSearchRegion'] = region;
    } else {
      out.remove('songSearchRegion');
    }
  }
  if (out['fontPreferences'] is Map) {
    final prefs = out['fontPreferences'] as Map;
    if (!['local', 'ezcd'].contains(prefs['mode'])) prefs.remove('mode');
    if (prefs['previewSize'] is num) {
      prefs['previewSize'] = (prefs['previewSize'] as num).clamp(1, 1000);
    }
  }
  return out;
}
