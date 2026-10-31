// Dart port of ezCD FontStyle / FontRuntime matching rules. IQ Online Studio, MIT.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

int? namedWeight(String value) {
  final s = unicode
      .nfkc(value)
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .toLowerCase();
  final compact = s.replaceAll(RegExp(r'[\s_-]+'), '');
  final explicit = RegExp(
    r'(?:^|[\s_-])(?:w|weight)?(1000|[1-9]00)(?:$|[\s_-])',
  ).firstMatch(s);
  if (explicit != null) return int.parse(explicit[1]!);
  final w = RegExp(r'(?:^|[\s_-])w([1-9])(?:$|[\s_-])').firstMatch(s);
  if (w != null) return int.parse(w[1]!) * 100;
  const english = {
    'extrablack': 950,
    'ultrablack': 950,
    'extrabold': 800,
    'ultrabold': 800,
    'semibold': 600,
    'demibold': 600,
    'extralight': 200,
    'ultralight': 200,
    'semilight': 350,
    'demilight': 350,
    'hairline': 100,
    'thin': 100,
    'light': 300,
    'book': 350,
    'medium': 500,
    'black': 900,
    'heavy': 900,
    'bold': 700,
    'regular': 400,
    'normal': 400,
    'roman': 400,
  };
  for (final e in english.entries) {
    if (compact == e.key ||
        RegExp('(?:^|[\\s_-])${e.key}(?:\$|[\\s_-])').hasMatch(s) ||
        e.key.length >= 8 && compact.contains(e.key)) {
      return e.value;
    }
  }
  const chinese = {
    '极细': 100,
    '極細': 100,
    '特细': 200,
    '特細': 200,
    '纤细': 200,
    '纖細': 200,
    '半粗': 600,
    '特粗': 800,
    '超粗': 900,
    '中等': 500,
    '常规': 400,
    '常規': 400,
    '标准': 400,
    '標準': 400,
    '细体': 300,
    '細體': 300,
    '粗体': 700,
    '粗體': 700,
  };
  for (final e in chinese.entries) {
    if (compact.contains(e.key)) return e.value;
  }
  return const {
    '细': 300,
    '細': 300,
    'l': 300,
    '中': 500,
    'm': 500,
    '粗': 700,
    'b': 700,
    '重': 900,
    'h': 900,
    'r': 400,
  }[compact];
}

List<Map<String, dynamic>> fontAxes(Map<String, dynamic> r) =>
    (r['axes'] as List? ?? [])
        .map((a) => Map<String, dynamic>.from(a))
        .toList();
int effectiveWeight(Map<String, dynamic> r) {
  for (final a in fontAxes(r)) {
    if (a['tag'] == 'wght') return (a['default'] as num).toInt().clamp(1, 1000);
  }
  final primary = namedWeight('${r['subfamily']}');
  if (primary != null && primary != 400) return primary;
  for (final v in [
    '${r['postScriptName'] ?? ''}',
    '${r['fullName']}',
    '${r['fileName']}'.replaceFirst(RegExp(r'\.[^.]*$'), ''),
  ]) {
    final n = namedWeight(
      v.replaceAll(
        RegExp(RegExp.escape('${r['family']}'), caseSensitive: false),
        '',
      ),
    );
    if (n != null && n != 400) return n;
  }
  final raw = (r['weight'] as num? ?? 400).toInt();
  return raw >= 1 && raw <= 9 ? raw * 100 : raw.clamp(1, 1000);
}

bool effectiveItalic(Map<String, dynamic> r) =>
    r['italic'] == true ||
    ['${r['subfamily']}', '${r['fullName']}', '${r['fileName']}'].any(
      (s) => RegExp(
        r'italic|oblique|slanted|斜体|斜體',
        caseSensitive: false,
      ).hasMatch(s.replaceAll('${r['family']}', '')),
    );
String familyKey(String s) => unicode.nfc(s).trim().toLowerCase();
int naturalCompare(String a, String b) {
  final re = RegExp(r'\d+|\D+');
  final aa = re.allMatches(a.toLowerCase()).map((m) => m[0]!).toList(),
      bb = re.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (int i = 0; i < aa.length && i < bb.length; i++) {
    final x = aa[i], y = bb[i];
    int n;
    if (RegExp(r'^\d').hasMatch(x) && RegExp(r'^\d').hasMatch(y)) {
      final xx = x.replaceFirst(RegExp(r'^0+'), ''),
          yy = y.replaceFirst(RegExp(r'^0+'), '');
      n = xx.length.compareTo(yy.length);
      if (n == 0) n = xx.compareTo(yy);
    } else {
      n = x.compareTo(y);
    }
    if (n != 0) return n;
  }
  return aa.length.compareTo(bb.length);
}

Map<String, dynamic> matchFont(
  List<Map<String, dynamic>> family,
  int weight,
  bool italic,
) {
  bool supports(Map<String, dynamic> f) =>
      effectiveItalic(f) == italic ||
      fontAxes(f).any(
        (a) => italic
            ? a['tag'] == 'ital' && a['max'] > 0 ||
                  a['tag'] == 'slnt' && (a['min'] < 0 || a['max'] > 0)
            : ['ital', 'slnt'].contains(a['tag']) &&
                  a['min'] <= 0 &&
                  a['max'] >= 0,
      );
  var list = family.where(supports).toList();
  if (list.isEmpty) list = family.toList();
  int distance(Map<String, dynamic> f) {
    for (final a in fontAxes(f)) {
      if (a['tag'] == 'wght' && weight >= a['min'] && weight <= a['max']) {
        return 0;
      }
    }
    return (effectiveWeight(f) - weight).abs();
  }

  list.sort((a, b) {
    var c = distance(a).compareTo(distance(b));
    if (c != 0) return c;
    c = (fontAxes(a).any((a) => a['tag'] == 'wght') ? 0 : 1).compareTo(
      fontAxes(b).any((a) => a['tag'] == 'wght') ? 0 : 1,
    );
    return c != 0 ? c : '${a['id']}'.compareTo('${b['id']}');
  });
  return list.first;
}

class LoadedFont {
  final String? family;
  final int weight;
  final bool italic;
  final List<ui.FontVariation> variations;
  const LoadedFont(
    this.family, {
    this.weight = 400,
    this.italic = false,
    this.variations = const [],
  });
  FontWeight get fontWeight =>
      FontWeight.values[(weight / 100).round().clamp(1, 9) - 1];
  TextStyle style(double size) => TextStyle(
    fontFamily: family,
    fontWeight: fontWeight,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    fontVariations: variations,
    fontSize: size,
  );
}
