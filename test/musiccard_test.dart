import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/renderer.dart';
import 'package:musiccardx/main.dart';
import 'package:musiccardx/fonts.dart';
import 'package:musiccardx/font_style.dart';
import 'package:musiccardx/color_picker.dart';
import 'package:photo_view/photo_view.dart';
import 'package:musiccardx/inline_preview.dart';
import 'package:musiccardx/compact_table.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChineseConverter chinese;
  setUpAll(() async {
    await CardDocument.initialize();
    chinese = ChineseConverter();
    await chinese.load();
    Directory('test-output').createSync();
    if (File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')
        .existsSync()) {
      final loader = FontLoader('Roboto');
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')
                .readAsBytesSync(),
          ),
        ),
      );
      await loader.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        Future.value(
          ByteData.sublistView(
            File(
              '../tooling/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytesSync(),
          ),
        ),
      );
      await icons.load();
    }
  });
  test('OpenCC results match bundled original library', () async {
    final cases = jsonDecode(
      File('test/fixtures/opencc_cases.json').readAsStringSync(),
    ) as List;
    for (final c in cases) {
      expect(
        chinese.convert(c['text'], c['mode']),
        c['expected'],
        reason: c['mode'],
      );
    }
  });
  test('manual fields and title formatting', () {
    final d = CardDocument.fresh();
    d.fields.addAll({
      'title': 'Song',
      'album artist': 'Various Artists',
      'date': '2026-10-30',
      'discnumber': '1',
      'totaldiscs': '2',
      'tracknumber': '3',
      'totaltracks': '12',
    });
    expect(d.evaluate(r'$if2(%artist%,%album artist%)'), 'Various Artists');
    expect(d.evaluate(r'[%datey%]'), '2026');
    expect(d.evaluate(r'$if(%title%,yes,no)'), 'yes');
    expect(d.evaluate(r'$num(%tracknumber%,2)'), '03');
    expect(d.metadata, '2026 · Disc 1 / 2: Track 03 / 12');
    expect(d.evaluate('manual input'), 'manual input');
  });
  test('rainbow percentage moves toward target', () {
    expect(resolveColor('r%0+#000000', Colors.white, Colors.red), Colors.black);
    expect(
      resolveColor('r%100+#000000', Colors.white, Colors.red).toARGB32(),
      Colors.red.toARGB32(),
    );
    expect(validColor('r%101'), false);
    expect(validColor('r%20+#114514'), true);
    expect(validColor('r%20+r%20'), false);
  });
  test('config roundtrip preserves fields and empty spacing', () {
    final d = CardDocument.fresh();
    d.fields['title'] = 'test';
    d.styles['titleValue']['letterSpacing'] = '';
    final copy = CardDocument.fromJson(mapv(jsonDecode(jsonEncode(d.data))));
    expect(copy.fields['title'], 'test');
    expect(copy.styles['titleValue']['letterSpacing'], '');
    expect(copy.lyrics['lineGap'], 40);
  });
  test('all backgrounds export PNG and X seeds are repeatable', () async {
    final rec = ui.PictureRecorder(), canvas = Canvas(rec);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 400, 260),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(400, 260), [
          const Color(0xfff7a467),
          const Color(0xff2253a7),
        ]),
    );
    canvas.drawCircle(
      const Offset(210, 120),
      70,
      Paint()..color = const Color(0xffffdfaa),
    );
    final p = rec.endRecording(), cover = await p.toImage(400, 260);
    p.dispose();
    final renderer = CardRenderer(chinese, FontRegistry()),
        d = CardDocument.fresh();
    d.fields.addAll({
      'title': 'MusicCardX',
      'artist': 'IQ Online Studio',
      'album': 'The independent edition',
      'date': '2026',
      'tracknumber': '1',
      'totaltracks': '12',
    });
    d.data['seed'] = 'mcx2026';
    d.styles['titleValue']['colorHex'] = 'r%20';
    for (final mode in backgrounds.keys) {
      d.data['backgroundStyle'] = mode;
      final r = await renderer.render(d, cover: cover);
      final bytes = await r.png();
      expect(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(r.size.height, 400);
      File('test-output/$mode.png').writeAsBytesSync(bytes);
      if (mode == 'fusion') {
        final again = await renderer.render(d, cover: cover);
        expect(await again.png(), bytes);
        again.image.dispose();
      }
      r.image.dispose();
    }
    d.data['backgroundStyle'] = 'fusion';
    d.data['irregularCoverMode'] = 'tile';
    d.data['coverCornerRadius'] = 180;
    d.data['customEnvironmentColorsEnabled'] = true;
    d.data['customEnvironmentColors'] = [
      '#d5b9a0',
      '#a8bdd4',
      '#acc5b6',
      '#d6b4be',
      '#d5cba4',
    ];
    d.lyrics.addAll({
      'enabled': true,
      'text': 'All the colours\nAll the songs\nMade by you',
      'dividerEnabled': true,
      'dividerTopHex': '#ff2233',
      'dividerMiddleHex': '#ffffff',
      'dividerBottomHex': '#2233ff',
      'yAlign': 'center',
      'xAlign': 'right',
      'colorHex': 'r%35',
      'blurStrength': 8,
      'blurOpacity': 100,
    });
    d.data['exportScale'] = 2;
    final lyrics = await renderer.render(d, cover: cover);
    File('test-output/lyrics-2x.png').writeAsBytesSync(await lyrics.png());
    expect(lyrics.size.height, 800);
    lyrics.image.dispose();
    final noCover = await renderer.render(d);
    File('test-output/no-cover.png').writeAsBytesSync(await noCover.png());
    noCover.image.dispose();
    cover.dispose();
  });
  test(
    'oversized output cancels before bitmap allocation without confirmation',
    () async {
      final d = CardDocument.fresh();
      d.styles['titleValue']['text'] = 'x' * 4000;
      expect(
        CardRenderer(chinese, FontRegistry()).render(d),
        throwsA(isA<RenderCancelledException>()),
      );
    },
  );
  test('ezCD v1 rejects unsafe paths and unknown versions', () {
    expect(FontRepository.validPath('fonts/a.ttf'), true);
    for (final s in [
      '/a.ttf',
      '../a.ttf',
      'a/../b',
      'a\\b',
      'a//b',
      'a/./b',
      'C:/a',
    ]) {
      expect(FontRepository.validPath(s), false);
    }
    expect(
      () => FontRepository.catalog({
        'format': 'ezcd-font-catalog',
        'version': 2,
        'fonts': [],
      }),
      throwsFormatException,
    );
    expect(
      FontRepository.catalog({
        'format': 'ezcd-font-catalog',
        'version': 1,
        'status': 'retired',
        'fonts': [],
      }),
      isEmpty,
    );
  });
  test('Dart TTC parsing and standalone face extraction', () async {
    final f = File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc');
    if (!f.existsSync()) return;
    final bytes = f.readAsBytesSync();
    final faces = Sfnt.inspect(bytes, 'CJK.ttc');
    expect(faces.length, greaterThan(1));
    for (final row in faces.take(2)) {
      final standalone = Sfnt.face(bytes, row['faceIndex']);
      final single = Sfnt.inspect(standalone, 'face.otf');
      expect(single.length, 1);
      expect(single.first['fullName'], row['fullName']);
    }
  });
  test(
    'ezCD staged update keeps last usable snapshot on hash failure',
    () async {
      final repo = FontRepository.instance;
      final temp = await Directory.systemTemp.createTemp('mcx-font-test');
      repo.root = temp;
      repo.mode = 'ezcd';
      repo.tree = 'test-tree';
      repo.revision = 'writer:old';
      final old = Uint8List.fromList([1, 2, 3]),
          next = Uint8List.fromList([4, 5, 6]);
      final oldHash = sha256.convert(old).toString(),
          newHash = sha256.convert(next).toString();
      repo.shared = [
        {
          'id': 'ez:writer:a',
          'sha256': oldHash,
          'path': 'fonts/a.ttf',
          'faceIndex': 0,
        },
      ];
      await File('${temp.path}/$oldHash.cache').writeAsBytes(old);
      bool valid = false, retired = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(fontIO, (call) async {
            if (call.arguments['path'] == 'ezcd-fonts.json') {
              return Uint8List.fromList(
                utf8.encode(
                  jsonEncode({
                    'format': 'ezcd-font-catalog',
                    'version': 1,
                    'status': retired ? 'retired' : 'active',
                    'writerId': 'writer',
                    'revision': retired ? 'retired' : 'new',
                    'fonts': retired
                        ? []
                        : [
                            {
                              'id': 'a',
                              'sha256': newHash,
                              'path': 'fonts/a.ttf',
                              'faceIndex': 0,
                            },
                          ],
                  }),
                ),
              );
            }
            return valid ? next : old;
          });
      await repo.refresh();
      expect(repo.revision, 'writer:old');
      expect(repo.shared.first['sha256'], oldHash);
      expect(repo.warning, contains('暂保留'));
      valid = true;
      await repo.refresh();
      expect(repo.revision, 'writer:new');
      expect(repo.shared.first['sha256'], newHash);
      retired = true;
      await repo.refresh();
      expect(repo.shared, isEmpty);
      repo.root = null;
      repo.mode = 'local';
      repo.tree = '';
      repo.revision = '';
      repo.warning = '';
      repo.local = [];
      repo.shared = [];
      await temp.delete(recursive: true);
    },
  );
  test(
    'local and ezCD sources resolve identical metadata weight and pixels',
    () async {
      final repo = FontRepository.instance;
      final base = await Directory.systemTemp.createTemp('font-source-parity');
      final bytes = await File(
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      ).readAsBytes();
      final hash = sha256.convert(bytes).toString();
      final row = Sfnt.inspect(bytes, 'DejaVuSans.ttf').single;
      final localPath = '${base.path}/$hash.font';
      await File(localPath).writeAsBytes(bytes);
      await File('${base.path}/$hash.cache').writeAsBytes(bytes);
      repo.root = base;
      repo.local = [
        {...row, 'id': 'local', 'sha256': hash, 'localPath': localPath},
      ];
      repo.mode = 'local';
      final localSpec = await repo.resolve('local');
      final localName = repo.name('local');
      final doc = CardDocument.fresh();
      doc.fields['title'] = 'Font weight 0123456789';
      doc.data['seed'] = '12345678';
      for (final style in doc.styles.values) {
        style['font'] = 'local';
      }
      final renderer = CardRenderer(chinese, FontRegistry());
      final a = await renderer.render(doc);
      final apng = await a.png();
      a.image.dispose();
      repo.shared = [
        {...row, 'id': 'ez:w:a', 'sha256': hash, 'path': 'fonts/font.ttf'},
      ];
      repo.mode = 'ezcd';
      final sharedSpec = await repo.resolve('ez:w:a');
      expect(repo.name('ez:w:a'), localName);
      expect(sharedSpec.weight, localSpec.weight);
      expect(sharedSpec.family, localSpec.family);
      for (final style in doc.styles.values) {
        style['font'] = 'ez:w:a';
      }
      final b = await renderer.render(doc);
      final bpng = await b.png();
      b.image.dispose();
      expect(sha256.convert(apng), sha256.convert(bpng));
      repo.local = [];
      repo.shared = [];
      repo.root = null;
      repo.mode = 'local';
      await base.delete(recursive: true);
    },
  );
  test('decimal seeds and old antialias migration', () {
    for (int i = 0; i < 50; i++) {
      expect(newSeed(), matches(RegExp(r'^\d{8}$')));
    }
    final d = CardDocument.fresh();
    d.data['textRenderingHint'] = 1;
    final loaded = CardDocument.fromJson(d.data);
    expect(loaded.n('textRenderingHint'), 4);
    expect(loaded.n('textAutoColorThreshold'), .5);
  });
  test('ezCD named weight and family matching rules', () {
    expect(namedWeight('ExtraLight'), 200);
    expect(namedWeight('SemiBold'), 600);
    expect(namedWeight('W3'), 300);
    expect(namedWeight('特粗'), 800);
    expect(naturalCompare('Family2', 'Family10'), lessThan(0));
    Map<String, dynamic> face(
      String id,
      int weight, {
      bool italic = false,
      List<Map<String, dynamic>> axes = const [],
    }) => {
      'id': id,
      'family': 'Test',
      'fullName': 'Test $id',
      'subfamily': id,
      'fileName': '$id.ttf',
      'weight': weight,
      'italic': italic,
      'axes': axes,
    };
    final light = face('Light', 400),
        regular = face('Regular', 400),
        bold = face('Bold', 400),
        slanted = face('Italic', 400, italic: true);
    expect(effectiveWeight(light), 300);
    expect(effectiveWeight(bold), 700);
    expect(
      matchFont([light, regular, bold, slanted], 300, false)['id'],
      'Light',
    );
    expect(
      matchFont([light, regular, bold, slanted], 700, false)['id'],
      'Bold',
    );
    expect(
      matchFont([light, regular, bold, slanted], 400, true)['id'],
      'Italic',
    );
    final variable = face(
      'Variable',
      400,
      axes: [
        {'tag': 'wght', 'min': 100, 'default': 450, 'max': 900},
      ],
    );
    expect(effectiveWeight(variable), 450);
    expect(matchFont([regular, variable], 550, false)['id'], 'Variable');
  });
  test(
    'font metadata equals ezCD fixtures and repaired runtime SFNT checksums',
    () async {
      for (final entry in {
        'Light': 300,
        'Regular': 400,
        'Medium': 500,
        'Bold': 700,
      }.entries) {
        final file = File('test/fixtures/fonts/${entry.key}.ttf');
        if (!file.existsSync()) continue;
        final bytes = await file.readAsBytes();
        final row = Sfnt.inspect(bytes, '${entry.key}.ttf').single;
        expect(row['weight'], entry.value);
        final fixed = Sfnt.runtimeFace(bytes, 0, row);
        final b = ByteData.sublistView(fixed);
        int sum = 0;
        for (int p = 0; p < fixed.length; p += 4) {
          int word = 0;
          for (int k = 0; k < 4; k++) {
            word = (word << 8) | (p + k < fixed.length ? fixed[p + k] : 0);
          }
          sum = (sum + word) & 0xffffffff;
        }
        expect(sum, 0xb1b0afba);
        expect(
          Sfnt.inspect(fixed, '${entry.key}.ttf').single['weight'],
          entry.value,
        );
        expect(b.lengthInBytes, greaterThan(12));
      }
    },
  );
  testWidgets(
    'font family label previews standard face and arrow expands independently',
    (tester) async {
      final repo = FontRepository.instance;
      final temp = Directory.systemTemp.createTempSync('manager-ui');
      repo.root = temp;
      repo.mode = 'local';
      repo.local = [];
      for (final n in ['Light', 'Regular', 'Bold']) {
        final bytes = File('test/fixtures/fonts/$n.ttf').readAsBytesSync();
        final row = Sfnt.inspect(bytes, '$n.ttf').single;
        final hash = sha256.convert(bytes).toString();
        final file = File('${temp.path}/$hash.font');
        file.writeAsBytesSync(bytes);
        repo.local.add({
          ...row,
          'id': n,
          'sha256': hash,
          'localPath': file.path,
        });
      }
      await tester.runAsync(() => repo.resolve('Regular', exact: true));
      await tester.pumpWidget(
        const MaterialApp(home: FontLibraryPage(selecting: true)),
      );
      await tester.pumpAndSettle();
      final regular = repo.local.firstWhere((r) => r['id'] == 'Regular');
      expect(find.text('${regular['fullName']}'), findsOneWidget);
      await tester.tap(find.byTooltip('展开字体家族'));
      await tester.pumpAndSettle();
      expect(find.text('Light (Light.ttf)'), findsOneWidget);
      await tester.tap(find.byTooltip('展开字体家族'));
      await tester.pumpAndSettle();
      expect(find.text('Light (Light.ttf)'), findsNothing);
      await tester.tap(find.text('${regular['fullName']}'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('字体信息'), findsOneWidget);
      expect(find.byTooltip('选择字体'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      repo.root = null;
      repo.local = [];
      temp.deleteSync(recursive: true);
    },
  );
  testWidgets('color picker supports RGB HSL HEX', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CardColorDialog(value: '#2196F3')),
    );
    await tester.pumpAndSettle();
    expect(find.text('R'), findsOneWidget);
    expect(find.text('H'), findsOneWidget);
    expect(find.text('HEX'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('dense workspace, pin and fullscreen viewport', (tester) async {
    tester.view.physicalSize = const Size(432, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async => null);
    final doc = CardDocument.fresh();
    await tester.pumpWidget(MusicCardX(doc, chinese));
    await tester.pumpAndSettle();
    expect(find.byType(BottomNavigationBar), findsNothing);
    for (final label in ['输入', '工作台', '设置']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('工作台'));
    await tester.pumpAndSettle();
    expect(find.byType(CompactTextTable), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('true'), findsNothing);
    expect(find.text('false'), findsNothing);
    await tester.tap(find.text('内容').first);
    await tester.pumpAndSettle();
    expect(find.text('批量设置 text'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('固定预览'));
    await tester.pumpAndSettle();
    expect(doc.data['previewPinned'], false);
    await tester.tap(find.byTooltip('固定预览'));
    await tester.pumpAndSettle();
    expect(doc.data['previewPinned'], true);
    expect(find.byType(InlinePreview), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('preview-image')));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoView), findsOneWidget);
    expect(tester.getSize(find.byType(PhotoView)).height, greaterThan(700));
    await tester.pageBack();
    await tester.pumpAndSettle();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MusicCardX(CardDocument.fresh(), chinese),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('工作台'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      File('test-output/workbench.png').writeAsBytesSync(
        (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List(),
      );
      image.dispose();
    });
    await tester.tap(find.text('封面圆角'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('独立四角'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(4));
    for (final label in ['↖', '↗', '↙', '↘']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      File('test-output/cover-shape-1.3.2.png').writeAsBytesSync(
        (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List(),
      );
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
