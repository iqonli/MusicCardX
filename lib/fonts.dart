import 'dialog_buttons.dart';
import 'storage_policy.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'font_style.dart';
import 'font_preview.dart';
import 'file_browser.dart';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const fontIO = MethodChannel('com.iqonli.musiccardx/platform');

class Sfnt {
  static List<Map<String, dynamic>> inspect(Uint8List bytes, String fileName) {
    final b = ByteData.sublistView(bytes);
    void range(int p, int n) {
      if (p < 0 || n < 0 || p + n > bytes.length) {
        throw const FormatException('字体表越界');
      }
    }

    range(0, 12);
    if (b.getUint32(0) == 0x74746366 &&
        (![0x00010000, 0x00020000].contains(b.getUint32(4)) ||
            b.getUint32(8) < 1 ||
            b.getUint32(8) > 128)) {
      throw const FormatException('字体集合无效');
    }
    final offsets = b.getUint32(0) == 0x74746366
        ? List.generate(b.getUint32(8).clamp(1, 128), (i) {
            range(12 + i * 4, 4);
            return b.getUint32(12 + i * 4);
          })
        : [0];
    return [
      for (int face = 0; face < offsets.length; face++)
        (() {
          final start = offsets[face];
          range(start, 12);
          if (![
            0x00010000,
            0x4f54544f,
            0x74727565,
          ].contains(b.getUint32(start))) {
            throw const FormatException('不支持的字体');
          }
          final count = b.getUint16(start + 4);
          if (count < 1 || count > 256) throw const FormatException('字体表过多');
          final tables = <String, (int, int)>{};
          for (int i = 0; i < count; i++) {
            final p = start + 12 + i * 16;
            range(p, 16);
            final tag = ascii.decode(bytes.sublist(p, p + 4));
            final offset = b.getUint32(p + 8), size = b.getUint32(p + 12);
            range(offset, size);
            if (tables.containsKey(tag)) throw const FormatException('字体表重复');
            tables[tag] = (offset, size);
          }
          final names = <int, String>{};
          final scores = <int, int>{};
          final nt = tables['name'];
          if (nt == null) throw const FormatException('缺少字体名称');
          final p = nt.$1;
          range(p, 6);
          if (nt.$2 < 6 || nt.$2 > 2 * 1024 * 1024) {
            throw const FormatException('字体名称表无效');
          }
          final n = b.getUint16(p + 2), strings = p + b.getUint16(p + 4);
          if (6 + n * 12 > nt.$2 ||
              strings < p + 6 + n * 12 ||
              strings > p + nt.$2) {
            throw const FormatException('字体名称表无效');
          }
          if (n > 10000) throw const FormatException('名称过多');
          for (int i = 0; i < n; i++) {
            final q = p + 6 + i * 12;
            range(q, 12);
            final platform = b.getUint16(q),
                encoding = b.getUint16(q + 2),
                language = b.getUint16(q + 4),
                id = b.getUint16(q + 6),
                length = b.getUint16(q + 8),
                offset = strings + b.getUint16(q + 10);
            range(offset, length);
            if (offset + length > p + nt.$2) {
              throw const FormatException('字体名称越界');
            }
            String text;
            if (platform == 0 ||
                platform == 3 && [0, 1, 10].contains(encoding)) {
              if (length % 2 != 0) continue;
              text = String.fromCharCodes(
                List.generate(length ~/ 2, (j) => b.getUint16(offset + j * 2)),
              );
            } else if (platform == 1 && encoding == 0) {
              const mac =
                  'ÄÅÇÉÑÖÜáàâäãåçéèêëíìîïñóòôöõúùûü†°¢£§•¶ß®©™´¨≠ÆØ∞±≤≥¥µ∂∑∏π∫ªºΩæø¿¡¬√ƒ≈∆«»… ÀÃÕŒœ–—“”‘’÷◊ÿŸ⁄€‹›ﬁﬂ‡·‚„‰ÂÊÁËÈÍÎÏÌÓÔÒÚÛÙıˆ˜¯˘˙˚¸˝˛ˇ';
              text = String.fromCharCodes(
                bytes
                    .sublist(offset, offset + length)
                    .map((n) => n < 128 ? n : mac.codeUnitAt(n - 128)),
              );
            } else {
              continue;
            }
            text = text
                .replaceAll(RegExp(r'[\x00-\x08\x0b-\x1f\x7f-\x9f]'), '')
                .trim();
            final score = platform == 3 && language == 0x409
                ? 100
                : platform == 0
                ? 90
                : platform == 1 && language == 0
                ? 80
                : platform == 3 && language & 0x3ff == 9
                ? 70
                : platform == 3
                ? 60
                : 10;
            if (text.isNotEmpty && score > (scores[id] ?? -1)) {
              names[id] = text;
              scores[id] = score;
            }
          }
          final family = names[16] ?? names[1] ?? names[4] ?? fileName;
          final sub = names[17] ?? names[2] ?? 'Regular';
          int weight = 400;
          bool italic = false;
          final os = tables['OS/2'];
          if (os != null && os.$2 >= 6) {
            weight = b.getUint16(os.$1 + 4).clamp(1, 1000);
            if (os.$2 >= 64) italic = b.getUint16(os.$1 + 62) & 0x201 != 0;
          }
          final head = tables['head'];
          if (head != null && head.$2 >= 46) {
            final flags = b.getUint16(head.$1 + 44);
            italic = italic || flags & 2 != 0;
            if (weight == 400 && flags & 1 != 0) weight = 700;
          }
          final post = tables['post'];
          if (post != null && post.$2 >= 8) {
            italic = italic || b.getInt32(post.$1 + 4) != 0;
          }
          final axes = <Map<String, dynamic>>[];
          final fv = tables['fvar'];
          if (fv != null && fv.$2 >= 16) {
            final base = fv.$1 + b.getUint16(fv.$1 + 4),
                num = b.getUint16(fv.$1 + 8),
                size = b.getUint16(fv.$1 + 10);
            if (num > 64 ||
                size < 20 ||
                base < fv.$1 + 16 ||
                base + num * size > fv.$1 + fv.$2) {
              throw const FormatException('可变轴无效');
            }
            for (int i = 0; i < num; i++) {
              final q = base + i * size;
              range(q, 20);
              if (b.getInt32(q + 4) > b.getInt32(q + 8) ||
                  b.getInt32(q + 8) > b.getInt32(q + 12)) {
                throw const FormatException('可变轴范围无效');
              }
              axes.add({
                'tag': ascii.decode(bytes.sublist(q, q + 4)),
                'min': b.getInt32(q + 4) / 65536,
                'default': b.getInt32(q + 8) / 65536,
                'max': b.getInt32(q + 12) / 65536,
              });
            }
          }
          final result = <String, dynamic>{
            'faceIndex': face,
            'family': family,
            'familyKey': familyKey(family),
            'subfamily': sub,
            'fullName': names[4] ?? '$family $sub',
            'fileName': fileName,
            'postScriptName': names[6] ?? '',
            'names': {for (final e in names.entries) '${e.key}': e.value},
            'weight': weight,
            'italic': italic,
            'axes': axes,
          };
          result['weight'] = effectiveWeight(result);
          result['italic'] = effectiveItalic(result);
          return result;
        })(),
    ];
  }

  static Uint8List runtimeFace(
    Uint8List bytes,
    int index,
    Map<String, dynamic> row,
  ) {
    final result = Uint8List.fromList(face(bytes, index));
    final b = ByteData.sublistView(result);
    final n = b.getUint16(4);
    int head = -1;
    final weight = effectiveWeight(row), italic = effectiveItalic(row);
    for (int i = 0; i < n; i++) {
      final p = 12 + i * 16,
          tag = b.getUint32(p),
          offset = b.getUint32(p + 8),
          length = b.getUint32(p + 12);
      if (tag == 0x4f532f32 && length >= 6) {
        b.setUint16(offset + 4, weight);
        if (length >= 64) {
          var flags = b.getUint16(offset + 62) & ~0x261;
          if (italic) flags |= 1;
          if (weight >= 700) flags |= 0x20;
          if (!italic && weight == 400) flags |= 0x40;
          b.setUint16(offset + 62, flags);
        }
      }
      if (tag == 0x68656164) {
        head = offset;
        b.setUint32(offset + 8, 0);
        if (length >= 46) {
          var flags = b.getUint16(offset + 44) & ~3;
          if (weight >= 700) flags |= 1;
          if (italic) flags |= 2;
          b.setUint16(offset + 44, flags);
        }
      }
    }
    int checksum(int offset, int length) {
      int sum = 0;
      for (int j = 0; j < length; j += 4) {
        int v = 0;
        for (int k = 0; k < 4; k++) {
          v = (v << 8) | (j + k < length ? result[offset + j + k] : 0);
        }
        sum = (sum + v) & 0xffffffff;
      }
      return sum;
    }

    for (int i = 0; i < n; i++) {
      final p = 12 + i * 16;
      b.setUint32(p + 4, checksum(b.getUint32(p + 8), b.getUint32(p + 12)));
    }
    if (head >= 0) {
      b.setUint32(
        head + 8,
        (0xb1b0afba - checksum(0, result.length)) & 0xffffffff,
      );
    }
    return result;
  }

  static Uint8List face(Uint8List bytes, int index) {
    final src = ByteData.sublistView(bytes);
    if (src.getUint32(0) != 0x74746366) {
      if (index != 0) throw const FormatException('字体面不存在');
      return bytes;
    }
    final count = src.getUint32(8);
    if (index < 0 || index >= count) throw const FormatException('字体面不存在');
    final base = src.getUint32(12 + index * 4), n = src.getUint16(base + 4);
    final tables = <List<int>>[];
    int length = 12 + 16 * n;
    for (int i = 0; i < n; i++) {
      final p = base + 12 + i * 16,
          off = src.getUint32(p + 8),
          size = src.getUint32(p + 12);
      if (off + size > bytes.length) throw const FormatException('字体表越界');
      tables.add([src.getUint32(p), src.getUint32(p + 4), off, size]);
      length += (size + 3) & ~3;
    }
    final result = Uint8List(length), out = ByteData.sublistView(result);
    result.setRange(0, 12, bytes.sublist(base, base + 12));
    int cursor = 12 + 16 * n, head = -1;
    for (int i = 0; i < n; i++) {
      final t = tables[i], p = 12 + i * 16;
      out.setUint32(p, t[0]);
      out.setUint32(p + 4, t[1]);
      out.setUint32(p + 8, cursor);
      out.setUint32(p + 12, t[3]);
      result.setRange(cursor, cursor + t[3], bytes.sublist(t[2], t[2] + t[3]));
      if (t[0] == 0x68656164) {
        head = cursor;
        out.setUint32(head + 8, 0);
      }
      cursor += (t[3] + 3) & ~3;
    }
    if (head >= 0) {
      int sum = 0;
      for (int i = 0; i < length; i += 4) {
        sum = (sum + out.getUint32(i)) & 0xffffffff;
      }
      out.setUint32(head + 8, (0xb1b0afba - sum) & 0xffffffff);
    }
    return result;
  }
}

class FontRepository extends ChangeNotifier {
  static final instance = FontRepository();
  Directory? root;
  String mode = 'local', tree = '', revision = '', warning = '';
  String sample = '中国智造，慧及全球 MusicCardX 0123456789';
  double previewSize = 100;
  List<Map<String, dynamic>> local = [], shared = [];
  bool working = false;
  bool _initialized = false;
  double progress = 0;
  final _loaded = <String, String>{};
  List<Map<String, dynamic>> get rows => mode == 'ezcd' ? shared : local;
  Future<void>? _initializing;
  Future<void> init() {
    if (_initializing != null) return _initializing!;
    if (root != null) return Future.value();
    return _initializing = _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  Future<void> _initialize() async {
    final p = await fontIO.invokeMethod<String>('storageRoot');
    if (p == null) {
      if (Platform.isAndroid) throw const FileSystemException('无法读取字体目录');
      return;
    }
    root = Directory('$p/fonts-flutter')..createSync(recursive: true);
    final f = File('${root!.path}/state.json');
    if (await f.exists()) {
      final d = jsonDecode(await f.readAsString());
      mode = d['mode'] ?? 'local';
      sample = d['sample'] == 'MusicCardX 字体预览 Aa 0123456789'
          ? sample
          : d['sample'] ?? sample;
      previewSize = (d['previewSize'] as num? ?? 100).toDouble();
      tree = d['tree'] ?? '';
      local = (d['local'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      shared = (d['shared'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      revision = d['revision'] ?? '';
    }
    if (!await f.exists()) await migrateLegacy(p);
    if (await f.exists()) {
      final state = jsonDecode(await f.readAsString());
      if (state['metadataVersion'] != 2) {
        for (final row in local) {
          try {
            final face = Sfnt.inspect(
              await File(row['localPath']).readAsBytes(),
              '${row['fileName']}',
            ).firstWhere((f) => f['faceIndex'] == row['faceIndex']);
            row.addAll(face);
          } catch (_) {}
        }
        await save();
      }
    }
    await refresh();
    _initialized = true;
    await pruneCache();
    try {
      await pruneLegacyDuplicates(p);
    } catch (_) {
      /* Keep legacy files if validation fails. */
    }
  }

  Future<void> migrateLegacy(String base) async {
    final file = File('$base/fonts/catalog.json');
    if (!await file.exists()) return;
    final old = jsonDecode(await file.readAsString());
    for (final item in old['fonts'] as List) {
      try {
        final src = item['source'];
        Uint8List? bytes;
        if (src == null) {
          bytes = await File('$base/fonts/${item['blob']}.font').readAsBytes();
        } else {
          bytes = await fontIO.invokeMethod<Uint8List>('uriRead', {
            'uri': src['uri'],
          });
          if (src['entry'] != null) {
            final archive = ZipDecoder().decodeBytes(bytes!, verify: true);
            final matches = archive.files.where((f) => f.name == src['entry']);
            if (matches.isEmpty) continue;
            bytes = Uint8List.fromList(matches.first.content as List<int>);
          }
        }
        if (bytes == null) continue;
        final hash = sha256.convert(bytes).toString();
        if (hash != item['blob']) continue;
        final dest = File('${root!.path}/$hash.font');
        if (!await dest.exists()) await dest.writeAsBytes(bytes);
        final face = Sfnt.inspect(
          bytes,
          item['filename'],
        ).firstWhere((f) => f['faceIndex'] == item['face']);
        local.add({
          ...face,
          'id': '$hash:${item['face']}',
          'sha256': hash,
          'localPath': dest.path,
        });
      } catch (_) {
        warning = '部分旧字体无法迁移，请重新导入或选择 ezCD 共享库';
      }
    }
    await save();
  }

  Future<void> pruneLegacyDuplicates(String base) async {
    final catalog = File('$base/fonts/catalog.json');
    if (!await catalog.exists()) return;
    final old = jsonDecode(await catalog.readAsString());
    var migrated = true;
    for (final item in old['fonts'] as List) {
      if (!local.any(
        (r) => r['sha256'] == item['blob'] && r['faceIndex'] == item['face'],
      )) {
        migrated = false;
        break;
      }
      final target = File('${root!.path}/${item['blob']}.font');
      if (!await target.exists() ||
          sha256.convert(await target.readAsBytes()).toString() !=
              item['blob']) {
        migrated = false;
        break;
      }
    }
    if (migrated) {
      await for (final file in Directory(
        '$base/fonts',
      ).list(followLinks: false)) {
        if (file is File &&
            RegExp(r'^[a-f0-9]{64}\.font$')
                .hasMatch(file.uri.pathSegments.last) &&
            (old['fonts'] as List).any(
              (item) => file.uri.pathSegments.last == '${item['blob']}.font',
            )) {
          await file.delete();
        }
      }
    }
  }

  Future<void> _saving = Future.value();
  Future<void> save() {
    final base = root!.path;
    final json = jsonEncode({
      'metadataVersion': 2,
      'sample': sample,
      'previewSize': previewSize,
      'mode': mode,
      'tree': tree,
      'local': local,
      'shared': shared,
      'revision': revision,
    });
    final task = _saving.catchError((_) {}).then((_) async {
      final f = File('$base/state.json.tmp');
      await f.writeAsString(json, flush: true);
      await f.rename('$base/state.json');
      notifyListeners();
    });
    _saving = task;
    return task;
  }

  static bool validPath(String path) {
    final parts = path.split('/');
    return parts.length == 2 &&
        !path.contains('\\') &&
        !RegExp(r'[\x00-\x1f\x7f]').hasMatch(path) &&
        parts.every(
          (p) => p.isNotEmpty && p != '.' && p != '..' && !p.contains(':'),
        );
  }

  static List<Map<String, dynamic>> catalog(Map<String, dynamic> d) {
    if (d['format'] != 'ezcd-font-catalog' ||
        d['version'] is! int ||
        d['version'] != 1) {
      throw const FormatException('未知 ezCD 字体清单格式／版本');
    }
    if (d['status'] == 'retired') return [];
    if (d['status'] != 'active' || d['fonts'] is! List) {
      throw const FormatException('无效字体清单');
    }
    return (d['fonts'] as List).map((v) {
      final r = Map<String, dynamic>.from(v);
      if (!validPath('${r['path']}') ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch('${r['sha256']}') ||
          r['faceIndex'] is! int ||
          r['faceIndex'] < 0 ||
          r['faceIndex'] >= 128) {
        throw const FormatException('字体路径、哈希或面索引无效');
      }
      r['id'] = 'ez:${d['writerId']}:${r['id']}';
      return r;
    }).toList();
  }

  Future<void> refresh() async {
    if (mode != 'ezcd' || tree.isEmpty) return;
    try {
      final bytes = await readTree('ezcd-fonts.json');
      final d = Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes!)));
      final next = catalog(d);
      if (d['status'] == 'active' &&
          revision == '${d['writerId']}:${d['revision']}') {
        warning = '';
        notifyListeners();
        return;
      }
      // Validate changes to fonts already in use before replacing the last usable snapshot.
      for (final row in next) {
        final prior = shared.where((r) => r['id'] == row['id']);
        if (prior.isNotEmpty &&
            await File('${root!.path}/${prior.first['sha256']}.cache')
                .exists()) {
          await this.bytes(row);
        }
      }
      shared = next;
      revision = '${d['writerId']}:${d['revision']}';
      warning = d['status'] == 'retired' ? 'ezCD 已停用该目录，请重新选择活动目录' : '';

      await save();
    } catch (e) {
      warning = '共享库读取失败，暂保留上次可用快照：$e';
      notifyListeners();
    }
  }

  Future<void> selectTree(BuildContext context) async {
    final picked = await browseFiles(context, directory: true);
    if (picked == null || picked.isEmpty) return;
    final previous = tree;
    tree = 'path:${picked.first}';
    warning = '';
    try {
      await refresh();
      if (warning.startsWith('共享库读取失败')) {
        tree = previous;
        throw FormatException(warning);
      }
    } finally {
      await save();
    }
  }

  Future<Uint8List?> readTree(String path, {int limit = 8388608}) async {
    if (tree.startsWith('path:')) {
      if (path != 'ezcd-fonts.json' && !validPath(path)) {
        throw const FormatException('无效路径');
      }
      final file = File('${tree.substring(5)}/$path');
      if (await file.length() > limit) throw const FormatException('文件超过大小限制');
      return file.readAsBytes();
    }
    return fontIO.invokeMethod<Uint8List>('treeRead', {
      'tree': tree,
      'path': path,
      'limit': limit,
    });
  }

  Future<void> source(String next) async {
    mode = next;

    await save();
    await refresh();
  }

  Future<void> importFiles(BuildContext context) async {
    if (mode != 'local') return;
    final picked = await browseFiles(
      context,
      extensions: {'ttf', 'otf', 'ttc', 'otc', 'zip'},
    );
    if (picked == null) return;
    final files = picked
        .map((p) => {'path': p, 'name': p.split('/').last})
        .toList();
    working = true;
    notifyListeners();
    int added = 0, skipped = 0, failed = 0, totalBytes = 0;
    try {
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        try {
          if (await File(file['path']!).length() > 256 * 1024 * 1024) {
            throw const FormatException('字体文件超过 256 MB');
          }
          final bytes = await File(file['path']!).readAsBytes();
          final name = '${file['name']}';
          final candidates = <String, Uint8List>{};
          if (name.toLowerCase().endsWith('.zip')) {
            final a = ZipDecoder().decodeBytes(bytes, verify: true);
            for (final e in a) {
              if (e.isFile &&
                  RegExp(
                    r'\.(ttf|otf|ttc|otc)$',
                    caseSensitive: false,
                  ).hasMatch(e.name)) {
                totalBytes += e.size;
                if (totalBytes > 256 * 1024 * 1024) {
                  throw const FormatException('字体批次超过 256 MB');
                }
                candidates[e.name] = Uint8List.fromList(e.content as List<int>);
              }
            }
          } else {
            totalBytes += bytes.length;
            if (totalBytes > 256 * 1024 * 1024) {
              throw const FormatException('字体批次超过 256 MB');
            }
            candidates[name] = bytes;
          }
          for (final entry in candidates.entries) {
            try {
              final hash = sha256.convert(entry.value).toString();
              final faces = Sfnt.inspect(
                entry.value,
                entry.key.split('/').last,
              );
              final dest = File('${root!.path}/$hash.font');
              if (!await dest.exists()) await dest.writeAsBytes(entry.value);
              for (final f in faces) {
                final id = '$hash:${f['faceIndex']}';
                if (local.any((r) => r['id'] == id)) {
                  skipped++;
                  continue;
                }
                local.add({
                  ...f,
                  'id': id,
                  'sha256': hash,
                  'localPath': dest.path,
                });
                added++;
              }
            } catch (_) {
              failed++;
            }
          }
        } catch (_) {
          failed++;
        }
        progress = (i + 1) / files.length;
        notifyListeners();
        await save();
      }
    } finally {
      working = false;
      warning = '导入成功 $added，跳过 $skipped，失败 $failed';
      notifyListeners();
    }
  }

  Future<void> remove(Set<String> ids) async {
    if (mode != 'local') return;
    local.removeWhere((e) => ids.contains(e['id']));

    await save();
    final used = local.map((e) => e['localPath']).toSet();
    await for (final f in root!.list()) {
      if (f is File && f.path.endsWith('.font') && !used.contains(f.path)) {
        await f.delete();
      }
    }
  }

  Future<Uint8List> bytes(Map<String, dynamic> row) async {
    if (row['localPath'] != null) return File(row['localPath']).readAsBytes();
    // Read the ezCD library in place. The source already persists this blob;
    // keeping another permanent copy can double multi-hundred-MB font libraries.
    final b = await readTree(row['path'], limit: 256 * 1024 * 1024);
    if (b == null || sha256.convert(b).toString() != row['sha256']) {
      throw const FormatException('共享字体哈希不匹配');
    }
    return b;
  }

  Future<void> pruneCache() async {
    if (root == null || !_initialized || working) return;
    await pruneFontStorage(
      root!,
      local.map((e) => '${e['localPath']}').toSet(),
    );
  }

  Map<String, dynamic>? lookup(String id) {
    final matches = rows.where(
      (r) => r['id'] == id || r['fullName'] == id || r['family'] == id,
    );
    return matches.isEmpty ? null : matches.first;
  }

  String name(String id) =>
      id.isEmpty ? '系统默认' : '${lookup(id)?['fullName'] ?? id}';
  Future<LoadedFont> resolve(
    String id, {
    bool bold = false,
    bool? italic,
    int? weight,
    bool exact = false,
  }) async {
    if (id.isEmpty) {
      return LoadedFont(
        null,
        weight: weight ?? (bold ? 700 : 400),
        italic: italic ?? false,
      );
    }
    await init();
    final selected = lookup(id);
    if (selected == null) {
      return LoadedFont(
        null,
        weight: weight ?? (bold ? 700 : 400),
        italic: italic ?? false,
      );
    }
    final desired = weight ?? (bold ? 700 : effectiveWeight(selected));
    final slant = italic ?? effectiveItalic(selected);
    final group = rows
        .where((r) => r['familyKey'] == selected['familyKey'])
        .toList();
    final row = exact ? selected : matchFont(group, desired, slant);
    final key = '${row['sha256']}:${row['faceIndex']}';
    var alias = _loaded[key];
    if (alias == null) {
      alias =
          'mcx_${sha256.convert(utf8.encode(key)).toString().substring(0, 16)}';
      final loader = FontLoader(alias)
        ..addFont(
          Future.value(
            ByteData.sublistView(
              Sfnt.runtimeFace(await bytes(row), row['faceIndex'], row),
            ),
          ),
        );
      await loader.load();
      _loaded[key] = alias;
    }
    final variations = <ui.FontVariation>[];
    int actual = effectiveWeight(row);
    for (final a in fontAxes(row)) {
      final tag = a['tag'];
      double? value;
      if (tag == 'wght') {
        value = desired.toDouble();
        actual = value
            .clamp((a['min'] as num).toDouble(), (a['max'] as num).toDouble())
            .round();
      }
      if (tag == 'ital') value = slant ? 1 : 0;
      if (tag == 'slnt') value = slant ? (a['min'] < 0 ? -12 : 12) : 0;
      if (value != null) {
        variations.add(
          ui.FontVariation(
            tag,
            value.clamp(
              (a['min'] as num).toDouble(),
              (a['max'] as num).toDouble(),
            ),
          ),
        );
      }
    }
    return LoadedFont(
      alias,
      weight: actual,
      italic: slant,
      variations: variations,
    );
  }

  Future<String?> family(String id) async =>
      (await resolve(id, exact: true)).family;
}

class FontLibraryPage extends StatefulWidget {
  final bool selecting;
  const FontLibraryPage({super.key, this.selecting = false});
  @override
  State<FontLibraryPage> createState() => _FontLibraryState();
}

class _FontLibraryState extends State<FontLibraryPage> {
  final repo = FontRepository.instance;
  String query = '';
  final selected = <String>{};
  final expanded = <String>{};
  String? error;
  @override
  void initState() {
    super.initState();
    repo.addListener(update);
    repo.init().catchError((e) {
      if (mounted) setState(() => error = '$e');
    });
  }

  void update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    repo.removeListener(update);
    super.dispose();
  }

  Future<void> run(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 1500),
            content: Text('$e'),
          ),
        );
      }
    }
  }

  Future<void> inspect(Map<String, dynamic> row) async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => FontPreviewPage(row: row, selecting: widget.selecting),
      ),
    );
    if (id != null && mounted) Navigator.pop(context, id);
  }

  Map<String, dynamic> standard(List<Map<String, dynamic>> group) {
    final sorted = group.toList()
      ..sort((a, b) {
        int c = (effectiveItalic(a) ? 1 : 0).compareTo(
          effectiveItalic(b) ? 1 : 0,
        );
        if (c != 0) return c;
        c = (effectiveWeight(a) - 400).abs().compareTo(
          (effectiveWeight(b) - 400).abs(),
        );
        if (c != 0) return c;
        c = ('${a['subfamily']}'.toLowerCase() == 'regular' ? 0 : 1).compareTo(
          '${b['subfamily']}'.toLowerCase() == 'regular' ? 0 : 1,
        );
        return c != 0 ? c : '${a['id']}'.compareTo('${b['id']}');
      });
    return sorted.first;
  }

  void selectGroup(List<Map<String, dynamic>> group) {
    final ids = group.map((r) => '${r['id']}').toSet();
    setState(() {
      if (ids.every(selected.contains)) {
        selected.removeAll(ids);
      } else {
        selected.addAll(ids);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in repo.rows) {
      if ('${r['family']} ${r['subfamily']} ${r['fullName']} ${r['fileName']}'
          .toLowerCase()
          .contains(query)) {
        groups.putIfAbsent('${r['familyKey']}', () => []).add(r);
      }
    }
    for (final g in groups.values) {
      g.sort((a, b) {
        int c = effectiveWeight(a).compareTo(effectiveWeight(b));
        if (c != 0) return c;
        c = (effectiveItalic(a) ? 1 : 0).compareTo(effectiveItalic(b) ? 1 : 0);
        if (c != 0) return c;
        c = naturalCompare('${a['subfamily']}', '${b['subfamily']}');
        if (c != 0) return c;
        c = naturalCompare('${a['fileName']}', '${b['fileName']}');
        return c != 0 ? c : '${a['id']}'.compareTo('${b['id']}');
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selecting ? '字体选择器' : '字体管理'),
        actions: [
          IconButton(
            tooltip: '刷新字体库',
            onPressed: repo.working ? null : () => run(repo.refresh),
            icon: const Icon(Icons.refresh),
          ),
          if (!widget.selecting && repo.mode == 'local')
            IconButton(
              tooltip: '导入字体或 ZIP',
              onPressed: repo.working
                  ? null
                  : () => run(() => repo.importFiles(context)),
              icon: const Icon(Icons.add),
            ),
          if (selected.isNotEmpty && repo.mode == 'local')
            IconButton(
              tooltip: '删除所选字体',
              onPressed: () async {
                final ok = await showCardDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    content: Text('删除 ${selected.length} 个字体面？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  run(() async {
                    await repo.remove(selected);
                    selected.clear();
                  });
                }
              },
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: repo.working,
        child: Column(
          children: [
            if (!widget.selecting)
              Padding(
                padding: const EdgeInsets.all(8),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'local', label: Text('导入字体')),
                    ButtonSegment(value: 'ezcd', label: Text('依赖于 ezCD')),
                  ],
                  selected: {repo.mode},
                  onSelectionChanged: (s) {
                    selected.clear();
                    run(() => repo.source(s.first));
                  },
                ),
              ),
            if (repo.mode == 'ezcd')
              ListTile(
                dense: true,
                title: const Text('ezCD 外部字体库（只读）'),
                subtitle: Text(
                  repo.tree.isEmpty ? '选择含 ezcd-fonts.json 的目录' : repo.tree,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: TextButton(
                  onPressed: () => run(() => repo.selectTree(context)),
                  child: const Text('选择目录'),
                ),
              ),
            if (repo.working) LinearProgressIndicator(value: repo.progress),
            if (repo.warning.isNotEmpty || error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  error ?? repo.warning,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: '筛选家族、全名或文件名',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (s) => setState(() => query = s.toLowerCase()),
              ),
            ),
            if (widget.selecting)
              ListTile(
                dense: true,
                title: const Text('系统默认'),
                onTap: () => Navigator.pop(context, ''),
              ),
            if (!widget.selecting &&
                repo.mode == 'local' &&
                repo.rows.isNotEmpty)
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(
                      () => selected.addAll(repo.rows.map((r) => '${r['id']}')),
                    ),
                    child: const Text('全选'),
                  ),
                  TextButton(
                    onPressed: () => setState(selected.clear),
                    child: const Text('取消选择'),
                  ),
                  Text('已选 ${selected.length}'),
                ],
              ),
            Expanded(
              child: groups.isEmpty
                  ? const Center(child: Text('暂无字体'))
                  : ListView(
                      children: [
                        for (final group
                            in (groups.entries.toList()..sort(
                                  (a, b) => naturalCompare(
                                    '${a.value.first['family']}',
                                    '${b.value.first['family']}',
                                  ),
                                ))
                                .map((e) => e.value))
                          if (group.length == 1)
                            ListTile(
                              dense: true,
                              title: Text('${group.first['fullName']}'),
                              subtitle: Text(
                                '${group.first['fileName']}  字重 ${group.first['weight']}',
                              ),
                              leading: !widget.selecting && repo.mode == 'local'
                                  ? Checkbox(
                                      value: selected.contains(
                                        group.first['id'],
                                      ),
                                      onChanged: (v) => setState(() {
                                        if (v == true) {
                                          selected.add(group.first['id']);
                                        } else {
                                          selected.remove(group.first['id']);
                                        }
                                      }),
                                    )
                                  : null,
                              onTap: () => inspect(group.first),
                            )
                          else
                            Column(
                              key: PageStorageKey(group.first['familyKey']),
                              children: [
                                ListTile(
                                  dense: true,
                                  leading:
                                      !widget.selecting && repo.mode == 'local'
                                      ? Checkbox(
                                          value: group.every(
                                            (r) => selected.contains(r['id']),
                                          ),
                                          onChanged: (_) => selectGroup(group),
                                        )
                                      : null,
                                  title: Text('${standard(group)['fullName']}'),
                                  subtitle: Text('${group.length} 个字体面'),
                                  onTap: () => selected.isNotEmpty
                                      ? selectGroup(group)
                                      : inspect(standard(group)),
                                  onLongPress:
                                      !widget.selecting && repo.mode == 'local'
                                      ? () => selectGroup(group)
                                      : null,
                                  trailing: IconButton(
                                    tooltip: '展开字体家族',
                                    constraints: const BoxConstraints.tightFor(
                                      width: 32,
                                      height: 32,
                                    ),
                                    padding: EdgeInsets.zero,
                                    onPressed: () => setState(() {
                                      final key = '${group.first['familyKey']}';
                                      if (!expanded.remove(key)) {
                                        expanded.add(key);
                                      }
                                    }),
                                    icon: Icon(
                                      expanded.contains(
                                            group.first['familyKey'],
                                          )
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                    ),
                                  ),
                                ),
                                if (expanded.contains(group.first['familyKey']))
                                  for (final row in group)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 16),
                                      child: ListTile(
                                        dense: true,
                                        title: Text(
                                          '${row['subfamily']} (${row['fileName']})',
                                        ),
                                        leading:
                                            !widget.selecting &&
                                                repo.mode == 'local'
                                            ? Checkbox(
                                                value: selected.contains(
                                                  row['id'],
                                                ),
                                                onChanged: (_) =>
                                                    selectGroup([row]),
                                              )
                                            : null,
                                        onTap: () => selected.isNotEmpty
                                            ? selectGroup([row])
                                            : inspect(row),
                                      ),
                                    ),
                              ],
                            ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
