import 'metadata_prompt.dart';
import 'fonts.dart';
import 'hex_text.dart';
import 'font_style.dart';
import 'config_normalization.dart';
import 'song_fields.dart';

import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

const styleLabels = <String, String>{
  'titleLabel': 'Title',
  'titleValue': 'Title文本',
  'artistLabel': 'Artist',
  'artistValue': 'Artist文本',
  'albumLabel': 'Album',
  'albumValue': 'Album第一行',
  'metaValue': 'Album第二行',
  'watermark': '水印',
};
const backgrounds = {
  'fusionClassic': '融合经典版',
  'fusionSoft': '融合新版-soft',
  'fusionHard': '融合新版-hard',
  'lightFlow': '流光',
  'mist': '雾化',
  'ink': '墨点',
  'sample': '采点',
  'blur': '模糊',
  'solid': '纯色',
};
const newBackgrounds = {'fusionSoft', 'fusionHard', 'lightFlow', 'mist'};
const seededBackgrounds = {
  'fusionClassic',
  'fusionSoft',
  'fusionHard',
  'lightFlow',
  'mist',
};
const ccModes = {
  'off': '关闭',
  't2s': 't2s',
  's2t': 's2t',
  's2twp': 's2twp',
  's2hk': 's2hk',
};
const platform = MethodChannel('com.iqonli.musiccardx/platform');
double numv(dynamic v, [double fallback = 0]) =>
    v is num ? v.toDouble() : double.tryParse('$v') ?? fallback;
Map<String, dynamic> mapv(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : {};
Map<String, dynamic> deepCopy(Map<String, dynamic> v) =>
    mapv(jsonDecode(jsonEncode(v)));
String newSeed() =>
    Random.secure().nextInt(100000000).toString().padLeft(8, '0');

class CardDocument {
  static late Map<String, dynamic> defaults;
  Map<String, dynamic> data;
  CardDocument(this.data) {
    normalizeBackgrounds();
    normalizeDocumentColors(data);
    enforceDisabledSongFields();
  }
  void normalizeBackgrounds() {
    if (data['backgroundStyle'] == 'fusion')
      data['backgroundStyle'] = 'fusionClassic';
    final mode = text('backgroundStyle');
    if (!backgrounds.containsKey(mode))
      data['backgroundStyle'] = 'fusionClassic';
    final saved = mapv(data['backgroundBlurStrengths']);
    final current = text('backgroundStyle');
    data['backgroundBlurStrengths'] = {
      for (final key in backgrounds.keys)
        key: numv(
          saved[key],
          key == current
              ? numv(data['blurStrength'], 300)
              : ((newBackgrounds.contains(key) || key == 'sample') ? 0 : 300),
        ).clamp(0, 500),
    };
    data['blurStrength'] = mapv(data['backgroundBlurStrengths'])[current];
  }

  void setBackground(String mode) {
    if (!backgrounds.containsKey(mode)) return;
    final values = mapv(data['backgroundBlurStrengths']);
    values[text('backgroundStyle')] = n('blurStrength', 300).clamp(0, 500);
    data['backgroundBlurStrengths'] = values;
    data['backgroundStyle'] = mode;
    data['blurStrength'] = numv(values[mode], 300);
  }

  static Future<void> initialize() async {
    defaults = mapv(
      jsonDecode(await rootBundle.loadString('assets/defaults.json')),
    );
  }

  factory CardDocument.fresh() => CardDocument({
    'musicCardXVersion': '1.5.1',
    'styleSchemaVersion': 16,
    'musicCardXSchemaVersion': 1,
    'exportScale': 1.0,
    'backgroundStyle': 'fusionClassic',
    'blurStrength': 300.0,
    'backgroundBlurStrengths': {
      for (final mode in backgrounds.keys)
        mode: (newBackgrounds.contains(mode) || mode == 'sample') ? 0.0 : 300.0,
    },
    'solidHex': '#000000',
    'coverShadowOpacity': 40.0,
    'coverShadowDepth': 3.0,
    'textRenderingHint': 4,
    'textAutoColorThreshold': 0.5,
    'imageFolder': '',
    'previewPinned': true,
    'coverSearchMinScore': 20.0,
    'coverSearchPreviewSize': 150,
    'coverSearchDownloadSize': 1000,
    'coverSearch_163': true,
    'coverSearch_apple': true,
    'coverSearch_appleweb': false,
    'coverSearchRegion': 'cn',
    'songSearch_163': true,
    'songSearch_apple': true,
    'songSearch_appleweb': false,
    'songSearch_qq': true,
    'songSearchRegion': 'cn',
    'metadataPromptTemplate': defaultMetadataPromptTemplate,
    'intentActions': <Map<String, dynamic>>[],
    'intentAutoCopy': true,
    'disabledSongFields': <String>[],
    'fontPreferences': <String, dynamic>{
      'mode': 'local',
      'tree': '',
      'sample': '中国智造，慧及全球 MusicCardX 0123456789',
      'previewSize': 100.0,
    },
    'imageFilename': 'MusicCardX-[%title%-][%artist%-][%album%-][%seed%]',
    'imageFormat': 'png',
    'jpegQuality': 95,
    'coverCornerRadius': 0.0,
    'irregularCoverMode': 'crop',
    'blurBackgroundCropPosition': 50.0,
    'rainbowSampleMaxSide': 150.0,
    'rainbowMode': 'auto',
    'rainbowCustomHex': '',
    'rainbowCustomSelection': 'hex',
    'paletteAlgorithm': 'celebi',
    'autoColorMode': 'auto',
    'textAlignMode': 'center',
    'monet': false,
    'coverShape': 'round',
    'coverExponent': 4,
    'customEnvironmentColorsEnabled': false,
    'customEnvironmentColors': <String>[],
    'textOpenCCMode': 'off',
    'lyricsOpenCCMode': 'off',
    'displayFontName': '',
    'seed': newSeed(),
    'fields': <String, dynamic>{
      'title': '',
      'artist': '',
      'album artist': '',
      'album': '',
      'date': '',
      'discnumber': '',
      'totaldiscs': '',
      'tracknumber': '',
      'totaltracks': '',
    },
    'coverPath': '',
    'style': deepCopy(mapv(defaults['style'])),
    'lyrics': deepCopy(mapv(defaults['lyrics'])),
  });
  factory CardDocument.fromJson(Map<String, dynamic> raw) {
    if (raw['style'] is! Map) throw const FormatException('缺少有效的 style 配置');
    raw = normalizeConfiguration(raw);
    final d = CardDocument.fresh();
    final fontDefaults = mapv(d.data['fontPreferences']);
    d.data.addAll(raw);
    if (!raw.containsKey('backgroundBlurStrengths'))
      d.data['backgroundBlurStrengths'] = <String, dynamic>{};
    d.data['fontPreferences'] = {
      ...fontDefaults,
      ...mapv(raw['fontPreferences']),
    };
    for (final k in styleLabels.keys) {
      final s = mapv(defaults['style'][k]);
      s.addAll(mapv(mapv(raw['style'])[k]));
      d.styles[k] = s;
    }
    final l = mapv(defaults['lyrics']);
    l.addAll(mapv(raw['lyrics']));
    d.data['lyrics'] = l;
    d.data['fields'] = normalizeSongFields(mapv(raw['fields']));
    if (d.data['textOpenCCMode'] == 's2tw') d.data['textOpenCCMode'] = 's2twp';
    if (d.data['lyricsOpenCCMode'] == 's2tw') {
      d.data['lyricsOpenCCMode'] = 's2twp';
    }
    final legacy = raw['musicCardXVersion'] == null;
    if (legacy && numv(raw['styleSchemaVersion']) < 11) {
      for (final item in [...d.styles.values, d.lyrics]) {
        if (numv(item['letterSpacing'], 99) == -1) item['letterSpacing'] = '';
      }
    }
    if (legacy &&
        numv(raw['styleSchemaVersion']) < 7 &&
        (defaults['legacyMeta'].contains(d.styles['metaValue']['text']) ||
            '${d.styles['metaValue']['text']}'.isEmpty)) {
      d.styles['metaValue']['text'] = defaults['style']['metaValue']['text'];
    }
    if (d.data['rainbowMode'] == 'sample') d.data['rainbowMode'] = 'auto';
    d.data['rainbowCustomSelection'] = '${d.data['rainbowCustomSelection']}'
        .replaceFirst('palette:', '');
    if (legacy) d.data['displayFontName'] = '';
    if (!backgrounds.containsKey(d.data['backgroundStyle'])) {
      d.data['backgroundStyle'] = 'fusionClassic';
    }
    for (final entry in [...d.styles.values, d.lyrics]) {
      for (final key in ['size', 'opacity', 'blurStrength', 'blurOpacity']) {
        entry[key] = numv(
          entry[key],
          key == 'size' ? 28 : 0,
        ).clamp(key == 'size' ? 0.001 : 0.0, key == 'size' ? 1000 : 255);
      }
      if (entry['letterSpacing'] != '') {
        entry['letterSpacing'] = numv(entry['letterSpacing'])
            .clamp(-1000, 1000);
      }
    }
    d.normalizeBackgrounds();
    final colors = d.data['customEnvironmentColors'];
    if (colors is! List ||
        colors.length != 5 ||
        !colors.every((e) => RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch('$e'))) {
      d.data['customEnvironmentColorsEnabled'] = false;
      d.data['customEnvironmentColors'] = <String>[];
    }
    for (final entry in [...d.styles.values, d.lyrics]) {
      if (!validColor('${entry['colorHex'] ?? ''}')) {
        entry.remove('colorHex');
      }
    }
    d.data['exportScale'] = numv(d.data['exportScale'], 1).clamp(.1, 10);
    for (final k in ['textOpenCCMode', 'lyricsOpenCCMode']) {
      if (!ccModes.containsKey(d.data[k])) d.data[k] = 'off';
    }
    d.data['textRenderingHint'] = 4;
    d.data['musicCardXVersion'] = '1.5.1';
    if (!raw.containsKey('coverShape') && d.n('coverCornerRadius') == 180) {
      d.data['coverShape'] = 'ellipse';
    }
    d.data['textAutoColorThreshold'] = numv(
      d.data['textAutoColorThreshold'],
      .5,
    ).clamp(0, 1);

    normalizeDocumentColors(d.data);
    d.data['jpegQuality'] = numv(
      d.data['jpegQuality'],
      95,
    ).round().clamp(1, 100);
    d.enforceDisabledSongFields();
    return d;
  }
  Set<String> get disabledSongFields => data['disabledSongFields'] is List
      ? (data['disabledSongFields'] as List)
            .whereType<String>()
            .where(songInputFields.containsKey)
            .toSet()
      : <String>{};
  void enforceDisabledSongFields() {
    final disabled = disabledSongFields;
    data['disabledSongFields'] = disabled.toList();
    final values = data['fields'];
    if (values is Map) {
      values.removeWhere((key, value) => disabled.contains(key));
    }
  }

  Map<String, dynamic> cleanSongFields(Map<String, dynamic> source) =>
      normalizeSongFields(source, disabled: disabledSongFields);
  Map<String, dynamic> get fields {
    enforceDisabledSongFields();
    return data['fields'];
  }

  Map<String, dynamic> get styles => data['style'];
  Map<String, dynamic> get lyrics => data['lyrics'];
  String text(String key) => '${data[key] ?? ''}';
  double n(String key, [double fallback = 0]) => numv(data[key], fallback);
  String get metadata =>
      TitleFormat(fields).evaluate(defaults['style']['metaValue']['text']);

  String evaluate(String expression) {
    return TitleFormat({
      ...fields,
      'seed': seededBackgrounds.contains(text('backgroundStyle'))
          ? text('seed')
          : '',
    }).evaluate(expression);
  }
}

// A local field formatter for existing styles; no foobar host is required.
class TitleFormat {
  final Map<String, dynamic> fields;
  final variables = <String, String>{};
  TitleFormat(this.fields);
  String evaluate(String s) => _eval(s, 0).text;
  ({String text, bool present}) _eval(String s, int depth) {
    if (depth > 24) throw const FormatException('表达式嵌套过深');
    final out = StringBuffer();
    bool present = false;
    for (int i = 0; i < s.length;) {
      if (i + 1 < s.length && s.substring(i, i + 2) == '//') {
        final end = s.indexOf('\n', i);
        i = end < 0 ? s.length : end + 1;
        continue;
      }
      if (i + 1 < s.length && s.substring(i, i + 2) == "''") {
        out.write("'");
        i += 2;
        continue;
      }
      if (s[i] == '\'') {
        final end = s.indexOf("'", i + 1);
        if (end < 0) {
          out.write(s.substring(i + 1));
          break;
        }
        out.write(s.substring(i + 1, end));
        i = end + 1;
        continue;
      }
      if (s[i] == '%') {
        final end = s.indexOf('%', i + 1);
        if (end >= 0) {
          final key = s.substring(i + 1, end).toLowerCase();
          final value = fields[key] is List
              ? (fields[key] as List).join(', ')
              : key == 'datey'
              ? ('${fields['date'] ?? ''}'.length >= 4
                    ? '${fields['date']}'.substring(0, 4)
                    : '${fields['date'] ?? ''}')
              : '${fields[key] ?? ''}';
          out.write(value);
          present |= value.isNotEmpty;
          i = end + 1;
          continue;
        }
      }
      if (s[i] == '[') {
        final end = _closing(s, i, '[', ']');
        if (end >= 0) {
          final r = _eval(s.substring(i + 1, end), depth + 1);
          if (r.present) {
            out.write(r.text);
            present = true;
          }
          i = end + 1;
          continue;
        }
      }
      if (s[i] == '\$') {
        final m = RegExp(r'^\$([a-zA-Z0-9_]+)\(').firstMatch(s.substring(i));
        if (m != null) {
          final open = i + m.end - 1;
          final end = _closing(s, open, '(', ')');
          if (end >= 0) {
            final args = _args(s.substring(open + 1, end));
            final name = m[1]!.toLowerCase();
            if ([
              'if',
              'if2',
              'if3',
              'ifequal',
              'ifgreater',
              'iflonger',
            ].contains(name)) {
              final first = _eval(args.isEmpty ? '' : args[0], depth + 1);
              String selected = '';
              if (name == 'if') {
                selected = first.present
                    ? (args.length > 1 ? args[1] : '')
                    : (args.length > 2 ? args[2] : '');
              } else if (name == 'if2') {
                selected = first.present
                    ? args[0]
                    : (args.length > 1 ? args[1] : '');
              } else if (name == 'if3') {
                for (int j = 0; j < args.length; j++) {
                  final value = _eval(args[j], depth + 1);
                  if (value.present || j == args.length - 1) {
                    selected = args[j];
                    break;
                  }
                }
              } else {
                final second = _eval(args.length > 1 ? args[1] : '', depth + 1);
                final yes = name == 'ifequal'
                    ? numv(first.text) == numv(second.text)
                    : name == 'ifgreater'
                    ? numv(first.text) > numv(second.text)
                    : first.text.length > numv(second.text);
                selected = args.length > (yes ? 2 : 3) ? args[yes ? 2 : 3] : '';
              }
              final value = _eval(selected, depth + 1);
              out.write(value.text);
              present |= first.present || value.present;
              i = end + 1;
              continue;
            }
            final a = args.map((e) => _eval(e, depth + 1)).toList();
            String at(int j) => j < a.length ? a[j].text : '';
            bool truth(int j) => j < a.length && a[j].present;
            int n(int j) => numv(at(j)).toInt();
            List<String> vals(int j) {
              final v = fields[at(j).toLowerCase()];
              return v is List
                  ? v.map((e) => '$e').toList()
                  : v == null || '$v'.isEmpty
                  ? []
                  : ['$v'];
            }

            bool? flag;
            String r;
            switch (name) {
              case 'if':
                r = truth(0) ? at(1) : at(2);
                break;
              case 'if2':
                r = truth(0) ? at(0) : at(1);
                break;
              case 'if3':
                r = a
                    .map((e) => e.text)
                    .firstWhere((e) => e.isNotEmpty, orElse: () => '');
                break;
              case 'get':
                r = variables[at(0)] ?? '';
                break;
              case 'put':
              case 'puts':
                variables[at(0)] = at(1);
                r = name == 'put' ? at(1) : '';
                break;
              case 'meta':
              case 'meta_sep':
              case 'meta_num':
              case 'meta_test':
                final list = vals(0);
                if (name == 'meta_num') {
                  r = '${list.length}';
                } else if (name == 'meta_test') {
                  flag = args.every((v) => vals(args.indexOf(v)).isNotEmpty);
                  r = flag ? '1' : '';
                } else if (name == 'meta_sep') {
                  r = list.join(at(1));
                  if (list.length > 1 && a.length > 2) {
                    r = '${list.take(list.length - 1).join(at(1))}${at(2)}${list.last}';
                  }
                } else {
                  r = a.length > 1
                      ? (n(1) >= 0 && n(1) < list.length ? list[n(1)] : '')
                      : list.join(', ');
                }
                flag ??= list.isNotEmpty;
                break;
              case 'info':
                r = '${fields[at(0).toLowerCase()] ?? ''}';
                flag = r.isNotEmpty;
                break;
              case 'add':
                r = '${a.fold<int>(0, (v, e) => v + numv(e.text).toInt())}';
                break;
              case 'sub':
                r = '${a.skip(1).fold<int>(n(0), (v, e) => v - numv(e.text).toInt())}';
                break;
              case 'mul':
                r = '${a.fold<int>(1, (v, e) => v * numv(e.text).toInt())}';
                break;
              case 'div':
                r = '${n(1) == 0 ? 0 : n(0) ~/ n(1)}';
                break;
              case 'mod':
                r = '${n(1) == 0 ? 0 : n(0) % n(1)}';
                break;
              case 'muldiv':
                r = '${n(2) == 0 ? 0 : (n(0) * n(1) / n(2)).round()}';
                break;
              case 'min':
                r = '${a.map((e) => numv(e.text).toInt()).reduce((x, y) => x < y ? x : y)}';
                break;
              case 'max':
                r = '${a.map((e) => numv(e.text).toInt()).reduce((x, y) => x > y ? x : y)}';
                break;
              case 'abs':
                r = '${n(0).abs()}';
                break;
              case 'greater':
                flag = n(0) > n(1);
                r = flag ? '1' : '';
                break;
              case 'strcmp':
                flag = at(0) == at(1);
                r = flag ? '1' : '';
                break;
              case 'stricmp':
                flag = at(0).toLowerCase() == at(1).toLowerCase();
                r = flag ? '1' : '';
                break;
              case 'strstr':
                r = '${at(0).indexOf(at(1)) + 1}';
                break;
              case 'strchr':
                r = '${at(0).indexOf(at(1)) + 1}';
                break;
              case 'strrchr':
                r = '${at(0).lastIndexOf(at(1)) + 1}';
                break;
              case 'left':
                r = at(0).substring(0, n(1).clamp(0, at(0).length));
                break;
              case 'right':
                r = at(0)
                    .substring((at(0).length - n(1)).clamp(0, at(0).length));
                break;
              case 'substr':
                r = at(0).substring(
                  (n(1) - 1).clamp(0, at(0).length),
                  n(2).clamp((n(1) - 1).clamp(0, at(0).length), at(0).length),
                );
                break;
              case 'cut':
                r = at(0).substring(0, n(1).clamp(0, at(0).length));
                break;
              case 'repeat':
                r = List.filled(n(1).clamp(0, 10000), at(0)).join();
                break;
              case 'insert':
                r = at(0).replaceRange(
                  n(2).clamp(0, at(0).length),
                  n(2).clamp(0, at(0).length),
                  at(1),
                );
                break;
              case 'pad':
                r = at(
                  0,
                ).padRight(n(1).clamp(0, 10000), at(2).isEmpty ? ' ' : at(2));
                break;
              case 'pad_right':
                r = at(0)
                    .padLeft(n(1).clamp(0, 10000), at(2).isEmpty ? ' ' : at(2));
                break;
              case 'len2':
                r = '${at(0).runes.fold<int>(0, (n, r) => n + (r > 255 ? 2 : 1))}';
                break;
              case 'char':
                r = String.fromCharCode(n(0).clamp(0, 0x10ffff));
                break;
              case 'crlf':
                r = '\r\n';
                break;
              case 'tab':
                r = List.filled(
                  a.isEmpty ? 1 : n(0).clamp(0, 100),
                  '\t',
                ).join();
                break;
              case 'caps':
              case 'caps2':
                r = (name == 'caps' ? at(0).toLowerCase() : at(0))
                    .replaceAllMapped(
                      RegExp(r'(^|\s)(\S)'),
                      (m) => '${m[1]}${m[2]!.toUpperCase()}',
                    );
                break;
              case 'ext':
                r =
                    at(0)
                        .replaceAll('\\', '/')
                        .split('/')
                        .last
                        .split('.')
                        .skip(1)
                        .lastOrNull ??
                    '';
                break;
              case 'filename':
              case 'filename_ext':
                final f = at(0).replaceAll('\\', '/').split('/').last;
                r = name == 'filename' && f.contains('.')
                    ? f.substring(0, f.lastIndexOf('.'))
                    : f;
                break;
              case 'directory_path':
                final f = at(0).replaceAll('\\', '/');
                r = f.contains('/') ? f.substring(0, f.lastIndexOf('/')) : '';
                break;
              case 'directory':
                final f = at(0).replaceAll('\\', '/').split('/');
                final index = f.length - 1 - (a.length > 1 ? n(1) : 1);
                r = index >= 0 && index < f.length ? f[index] : '';
                break;
              case 'select':
                r = n(0) > 0 && n(0) < a.length ? at(n(0)) : '';
                break;
              case 'year':
                r = RegExp(r'\d{4}').firstMatch(at(0))?[0] ?? '';
                break;
              case 'month':
                r = at(0).split('-').elementAtOrNull(1) ?? '';
                break;
              case 'day_of_month':
                r = at(0).split('-').elementAtOrNull(2) ?? '';
                break;
              case 'date':
                r = at(0).split(' ').first;
                break;
              case 'time':
                r = at(0).split(' ').elementAtOrNull(1) ?? '';
                break;
              case 'xor':
                flag = a.where((v) => v.present).length.isOdd;
                r = flag ? '1' : '';
                break;
              case 'num':
                r = at(0).padLeft(numv(at(1), 1).toInt().clamp(0, 100), '0');
                break;
              case 'len':
                r = at(0).runes.length.toString();
                break;
              case 'and':
                r = a.every((e) => e.present) ? '1' : '';
                break;
              case 'or':
                r = a.any((e) => e.present) ? '1' : '';
                break;
              case 'not':
                r = truth(0) ? '' : '1';
                break;
              case 'upper':
                r = at(0).toUpperCase();
                break;
              case 'lower':
                r = at(0).toLowerCase();
                break;
              case 'trim':
                r = at(0).trim();
                break;
              case 'replace':
                r = at(0);
                for (int j = 1; j + 1 < a.length; j += 2) {
                  if (at(j).isNotEmpty) r = r.replaceAll(at(j), at(j + 1));
                }
                break;
              default:
                throw FormatException('不支持的标题格式函数：\$${m[1]}');
            }
            out.write(r);
            present |=
                flag ??
                ([
                      'and',
                      'or',
                      'not',
                      'xor',
                      'greater',
                      'strcmp',
                      'stricmp',
                    ].contains(name)
                    ? r.isNotEmpty
                    : a.any((e) => e.present));
            i = end + 1;
            continue;
          }
        }
      }
      out.write(s[i++]);
    }
    return (text: out.toString(), present: present);
  }

  int _closing(String s, int start, String left, String right) {
    int n = 0;
    bool quote = false;
    for (int i = start; i < s.length; i++) {
      if (s[i] == "'") quote = !quote;
      if (quote) continue;
      if (s[i] == left) n++;
      if (s[i] == right) {
        n--;
        if (n == 0) return i;
      }
    }
    return -1;
  }

  List<String> _args(String s) {
    final result = <String>[];
    int start = 0, n = 0;
    bool quote = false;
    for (int i = 0; i < s.length; i++) {
      if (s[i] == "'") quote = !quote;
      if (quote) continue;
      if (s[i] == '(' || s[i] == '[') n++;
      if (s[i] == ')' || s[i] == ']') n--;
      if (s[i] == ',' && n == 0) {
        result.add(s.substring(start, i));
        start = i + 1;
      }
    }
    result.add(s.substring(start));
    return result;
  }
}

class _Trie {
  final Map<int, _Trie> children = {};
  String? value;
  _Trie.fromGroup(List<dynamic> group) {
    for (final dict in group.reversed) {
      for (final word in '$dict'.split('|')) {
        final split = word.indexOf(' ');
        if (split < 0) continue;
        var node = this;
        for (final rune in word.substring(0, split).runes) {
          node = node.children.putIfAbsent(rune, () => _Trie.empty());
        }
        node.value = word.substring(split + 1).split(' ').first;
      }
    }
  }
  _Trie.empty();
  List<String> run(String s, {bool segment = false}) {
    final chars = s.runes.toList();
    final out = <String>[];
    final unmatched = <int>[];
    for (int i = 0; i < chars.length;) {
      var node = this;
      int end = -1;
      String? replacement;
      for (int j = i; j < chars.length; j++) {
        final next = node.children[chars[j]];
        if (next == null) break;
        node = next;
        if (node.value != null) {
          end = j + 1;
          replacement = node.value;
        }
      }
      if (end < 0) {
        unmatched.add(chars[i++]);
      } else {
        if (unmatched.isNotEmpty) {
          out.add(String.fromCharCodes(unmatched));
          unmatched.clear();
        }
        out.add(
          segment ? String.fromCharCodes(chars.sublist(i, end)) : replacement!,
        );
        i = end;
      }
    }
    if (unmatched.isNotEmpty) out.add(String.fromCharCodes(unmatched));
    return out;
  }
}

class ChineseConverter {
  late Map<String, dynamic> configs;
  final Map<
    String,
    ({List<_Trie> normalize, _Trie? segment, List<_Trie> convert})
  >
  _cache = {};
  Future<void> load() async {
    configs = mapv(
      jsonDecode(await rootBundle.loadString('assets/opencc.json')),
    );
  }

  String convert(String text, String mode) {
    if (mode == 'off') return text;
    final c = _cache.putIfAbsent(mode, () {
      final raw = configs[mode];
      return (
        normalize: [
          for (final g in raw['normalizationChain'] ?? []) _Trie.fromGroup(g),
        ],
        segment: raw['segmentation'] == null
            ? null
            : _Trie.fromGroup(raw['segmentation']),
        convert: [for (final g in raw['conversionChain']) _Trie.fromGroup(g)],
      );
    });
    var result = text;
    for (final t in c.normalize) {
      result = t.run(result).join();
    }
    var segments = c.segment?.run(result, segment: true) ?? [result];
    for (final t in c.convert) {
      segments = segments.map((s) => t.run(s).join()).toList();
    }
    return segments.join();
  }
}

Color tokenColor(String token, Color fallback) {
  final s = token.trim().toLowerCase().replaceFirst('#', '');
  if (s == 'black') return const Color(0xff121212);
  if (s == 'white') return const Color(0xfffafafa);
  return RegExp(r'^[0-9a-f]{6}$').hasMatch(s)
      ? Color(0xff000000 | int.parse(s, radix: 16))
      : fallback;
}

bool validColor(String s, {bool rainbow = true}) {
  if (s.trim().isEmpty) return true;
  if (RegExp(
    r'^#?(?:[0-9a-fA-F]{6}|black|white)$',
    caseSensitive: false,
  ).hasMatch(s.trim())) {
    return true;
  }
  final m = RegExp(
    r'^(?:rainbow|r)%\s*(\d+(?:\.\d{1,3})?|\.\d{1,3})(?:\s*\+\s*(.+))?$',
    caseSensitive: false,
  ).firstMatch(s.trim());
  return rainbow &&
      m != null &&
      numv(m[1]) <= 100 &&
      (m[2] == null || validColor(m[2]!, rainbow: false) && m[2]!.isNotEmpty);
}

Color resolveColor(String spec, Color base, Color target) {
  final m = RegExp(
    r'^(?:rainbow|r)%\s*([\d.]+)(?:\s*\+\s*(.+))?$',
    caseSensitive: false,
  ).firstMatch(spec.trim());
  if (m != null) {
    return Color.lerp(
      m[2] == null ? base : tokenColor(m[2]!, base),
      target,
      numv(m[1]).clamp(0, 100) / 100,
    )!;
  }
  return tokenColor(spec, base);
}

Color opacity(Color c, dynamic alpha) =>
    c.withValues(alpha: numv(alpha, 255).clamp(0, 255) / 255);
double luminance(Color c) => .299 * c.r + .587 * c.g + .114 * c.b;

class FontRegistry {
  final Map<String, String> names = {};
  Future<String?> family(String id) async {
    try {
      final repo = FontRepository.instance;
      final result = await repo.family(id);
      for (final row in repo.rows) {
        names['${row['id']}'] = '${row['fullName']}';
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<LoadedFont> resolve(
    String id, {
    bool bold = false,
    bool? italic,
    int? weight,
  }) async {
    try {
      return await FontRepository.instance.resolve(
        id,
        bold: bold,
        italic: italic,
        weight: weight,
      );
    } catch (_) {
      return LoadedFont(
        null,
        weight: bold ? 700 : 400,
        italic: italic ?? false,
      );
    }
  }

  void clear() {}
}
