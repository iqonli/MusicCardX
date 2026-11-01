import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/song_fields.dart';
import 'package:musiccardx/audio_import.dart';
import 'package:musiccardx/compact_table.dart';
import 'package:musiccardx/cover_shape.dart';
import 'package:musiccardx/inline_preview.dart';
import 'package:musiccardx/palette_tools.dart';
import 'package:musiccardx/font_preview.dart';
import 'package:musiccardx/fonts.dart';
import 'package:crypto/crypto.dart';

import 'dart:convert';

Future<ui.Image> image() async {
  final r = ui.PictureRecorder();
  Canvas(
    r,
  ).drawRect(const Rect.fromLTWH(0, 0, 100, 100), Paint()..color = Colors.red);
  final p = r.endRecording();
  final i = await p.toImage(100, 100);
  p.dispose();
  return i;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(CardDocument.initialize);
  test(
    'default Album expression preserves separator for every tag combination',
    () {
      final d = CardDocument.fresh();
      final expression = d.styles['metaValue']['text'] as String;
      for (final c in [
        (
          {
            'date': '2026',
            'discnumber': '1',
            'tracknumber': '3',
            'totaldiscs': '2',
            'totaltracks': '12',
          },
          '2026 · Disc 1 / 2: Track 03 / 12',
        ),
        ({'date': '2026', 'tracknumber': '3'}, '2026 · Track 03'),
        ({'date': '2026', 'discnumber': '1'}, '2026 · Disc 1'),
        ({'date': '2026'}, '2026'),
        ({'tracknumber': '3'}, 'Track 03'),
        (<String, String>{}, ''),
      ]) {
        d.data['fields'] = c.$1;
        expect(d.evaluate(expression), c.$2);
      }
      expect(
        TitleFormat({'date': '2026'}).evaluate(r'[$if(%date%,exists,)]'),
        'exists',
      );
    },
  );
  test(
    'JSON fields discard invalid values while preserving tags and lists',
    () {
      expect(
        normalizeSongFields({
          ' TITLE ': ' A ',
          'artist': ['A', null, {}, false, ''],
          'bad': false,
          'nested': {},
          'empty': ' ',
          'null': null,
          'tracknumber': 3,
        }),
        {
          'title': 'A',
          'artist': ['A'],
          'tracknumber': '3',
        },
      );
      final d = CardDocument.fresh();
      d.data['unknown'] = 123;
      d.data['blurStrength'] = {'invalid': true};
      d.styles['titleValue'].addAll({
        'unknown': true,
        'size': null,
        'colorHex': 'wrong',
        'letterSpacing': 2.5,
      });
      final clean = CardDocument.fromJson(d.data);
      expect(clean.data.containsKey('unknown'), false);
      expect(clean.n('blurStrength'), 300);
      expect(clean.styles['titleValue'].containsKey('unknown'), false);
      expect(clean.styles['titleValue']['size'], 28);
      expect(clean.styles['titleValue']['colorHex'], '');
      expect(clean.styles['titleValue']['letterSpacing'], 2.5);
    },
  );
  for (final ext in ['mp3', 'flac', 'm4a', 'ogg', 'opus', 'wav']) {
    test('pure Dart reads $ext file tags', () {
      final a = readAudioInformation('test/fixtures/audio/tags.$ext');
      expect(a.fields['title'], '测试歌曲');
      expect(a.fields['artist'], 'Track Artist');
      expect(a.fields['album'], 'Test Album');
      if (['mp3', 'flac', 'm4a', 'ogg', 'opus'].contains(ext)) {
        expect(a.fields['album artist'], 'Album Artist');
      }
      if (ext != 'wav') {
        expect(a.fields['tracknumber'], '3');
        expect(a.fields['totaltracks'], '12');
      }
    });
  }
  test('embedded audio cover is read as bytes', () {
    final a = readAudioInformation('test/fixtures/audio/cover.mp3');
    expect(a.cover, File('test/fixtures/audio/cover.png').readAsBytesSync());
    expect(a.lyrics, '第一行\n第二行');
  });
  test(
    'standard ID3 USLT preserves the first character and multiline lyrics',
    () {
      expect(
        readAudioInformation('test/fixtures/audio/lyrics.mp3').lyrics,
        '真正的歌词\n第二行',
      );
    },
  );
  test('each shape uses its own radius parameter', () {
    final d = CardDocument.fresh();
    d.data['coverCornerRadius'] = 0;
    for (final type in ['round', 'continuous', 'bevel', 'concave']) {
      d.data['coverShape'] = type;
      d.data['coverShapeParameters'] = {
        type: {'coverCornerRadius': 100},
      };
      expect(
        coverShape(
          const Rect.fromLTWH(0, 0, 360, 360),
          d,
        ).contains(const Offset(1, 1)),
        false,
        reason: type,
      );
      d.data['coverShapeParameters'] = {
        type: {'coverCornerRadius': 0},
      };
      expect(
        coverShape(
          const Rect.fromLTWH(0, 0, 360, 360),
          d,
        ).contains(const Offset(1, 1)),
        true,
        reason: type,
      );
    }
  });
  testWidgets(
    'table has no numeric cap and content/font have only upper caps',
    (t) async {
      String? header, cell;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompactTextTable(
              columns: const {
                'element': '元素',
                'text': '内容',
                'font': '字体',
                'size': '字号',
                'hex': 'HEX',
              },
              rows: [
                ['Title', 'x' * 80, 'f' * 80, '1', 'a' * 100],
                ['Album', 'x', 'f', '123456789', 'r%10'],
              ],
              family: 'Roboto',
              onHeader: (k) => header = k,
              onCell: (r, k) => cell = '$r:$k',
            ),
          ),
        ),
      );
      final table = t.widget<Table>(find.byType(Table));
      double width(int i) => (table.columnWidths![i] as FixedColumnWidth).value;
      expect(width(1), 212);
      expect(width(2), 192);
      expect(width(3), greaterThan(40));
      expect(width(4), greaterThan(400));
      for (final value in ['Title', 'Album', '123456789', 'a' * 100]) {
        final p = t.renderObject<RenderParagraph>(find.text(value));
        expect(
          p.didExceedMaxLines,
          false,
          reason: 'Uncapped column must fit its actual text',
        );
      }
      await t.tap(find.text('内容'));
      expect(header, 'text');
      await t.tap(find.text('Title'));
      expect(cell, '0:element');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'inline preview pans with two fingers without introducing zoom and tap opens',
    (t) async {
      final i = await image();
      var taps = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 150,
                child: InlinePreview(image: i, onTap: () => taps++),
              ),
            ),
          ),
        ),
      );
      final target = find.byType(InlinePreview), center = t.getCenter(target);
      await t.tap(target);
      expect(taps, 1);
      final a = await t.startGesture(center - const Offset(40, 0), pointer: 1);
      final b = await t.startGesture(center + const Offset(40, 0), pointer: 2);
      await a.moveBy(const Offset(20, 10));
      await b.moveBy(const Offset(20, 10));
      await t.pump();
      final transforms = t
          .widgetList<Transform>(
            find.descendant(of: target, matching: find.byType(Transform)),
          )
          .toList();
      expect(transforms.first.transform.storage[12], closeTo(20, .01));
      expect(transforms.first.transform.storage[13], closeTo(10, .01));
      expect(transforms.last.transform.storage[0], closeTo(1, .001));
      await a.moveBy(const Offset(-20, 0));
      await b.moveBy(const Offset(20, 0));
      await t.pump();
      expect(
        t
            .widgetList<Transform>(
              find.descendant(of: target, matching: find.byType(Transform)),
            )
            .last
            .transform
            .storage[0],
        greaterThan(1),
      );
      await a.up();
      await b.up();
      await t.pumpWidget(const SizedBox());
      i.dispose();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'point page hides check until five labels and shows choice order above markers',
    (t) async {
      final i = await image();
      await t.pumpWidget(
        MaterialApp(
          home: PalettePointPage(
            image: i,
            initial: const [],
            algorithm: 'histogram',
          ),
        ),
      );
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      expect(find.byTooltip('确定'), findsNothing);
      expect(find.text('1'), findsNothing);
      await t.tap(find.text('开始连续选取5个'));
      await t.pump();
      final markers = find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onPanUpdate != null,
      );
      expect(markers, findsNWidgets(10));
      for (int n = 0; n < 5; n++) {
        await t.tap(markers.at(n));
        await t.pump();
      }
      expect(find.byTooltip('确定'), findsOneWidget);
      for (int n = 1; n <= 5; n++) {
        expect(find.text('$n'), findsOneWidget);
      }
      expect(find.text('重新连续选取5个'), findsOneWidget);
      await t.tap(markers.at(1));
      await t.pump();
      expect(find.byTooltip('确定'), findsNothing);
      expect(
        find.descendant(of: markers.at(1), matching: find.byType(Text)),
        findsNothing,
      );
      expect(
        find.descendant(of: markers.at(2), matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: markers.at(4), matching: find.text('4')),
        findsOneWidget,
      );
      expect(find.text('5'), findsNothing);
      final label = find.descendant(
        of: markers.at(2),
        matching: find.text('2'),
      );
      expect(
        (t.getCenter(label) - t.getCenter(markers.at(2))).distance,
        lessThan(.01),
      );
      final circles = t
          .widgetList<Container>(
            find.descendant(
              of: markers.at(2),
              matching: find.byType(Container),
            ),
          )
          .where((w) => w.decoration is BoxDecoration)
          .toList();
      final ring = circles.firstWhere(
        (w) => (w.constraints!.maxWidth - 35.7).abs() < .001,
      );
      final point = circles.firstWhere(
        (w) => (w.constraints!.maxWidth - 17.85).abs() < .001,
      );
      final ringDecoration = ring.decoration! as BoxDecoration;
      expect(ringDecoration.color, isNull);
      expect(ringDecoration.border!.top.color.a, closeTo(.7, .005));
      final color = (point.decoration! as BoxDecoration).color!;
      expect(
        t.widget<Text>(label).style!.color!.toARGB32(),
        0xff000000 | (~color.toARGB32() & 0xffffff),
      );
      await t.tap(markers.at(5));
      await t.pump();
      expect(
        find.descendant(of: markers.at(5), matching: find.text('5')),
        findsOneWidget,
      );
      expect(find.text('重新连续选取5个'), findsOneWidget);
      await t.tap(find.text('重新连续选取5个'));
      await t.pump();
      expect(find.byTooltip('确定'), findsNothing);
      for (int n = 1; n <= 5; n++) {
        expect(find.text('$n'), findsNothing);
      }
      final sizes = t
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(PalettePointPage),
              matching: find.byType(SizedBox),
            ),
          )
          .where(
            (w) =>
                w.width != null &&
                w.height != null &&
                (w.width! - 35.7).abs() < .001 &&
                (w.height! - 35.7).abs() < .001,
          );
      expect(sizes.length, 10);
      await t.pumpWidget(const SizedBox());
      i.dispose();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'font preview changes actual weight, uses black on white and persists sample',
    (t) async {
      final repo = FontRepository.instance;
      final temp = Directory.systemTemp.createTempSync('mcx-preview');
      repo.root = temp;
      repo.local = [];
      repo.mode = 'local';
      final bytes = File('test/fixtures/fonts/WeightVariable.ttf')
          .readAsBytesSync();
      final row = Sfnt.inspect(bytes, 'WeightVariable.ttf').single;
      final hash = sha256.convert(bytes).toString();
      final path = File('${temp.path}/font.ttf')..writeAsBytesSync(bytes);
      repo.local.add({
        ...row,
        'id': 'variable-preview',
        'sha256': hash,
        'localPath': path.path,
      });
      repo.sample = '中国智造，慧及全球 MusicCardX 0123456789';
      await t.runAsync(() => repo.resolve('variable-preview'));
      await t.pumpWidget(
        MaterialApp(home: FontPreviewPage(row: repo.local.single)),
      );
      await t.pumpAndSettle();
      final input = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '预览文本',
      );
      await t.enterText(input, '自定义预览ABC');
      await t.pump();
      await t.tap(find.text('+100'));
      await t.pumpAndSettle();
      final fontText = t
          .widgetList<Text>(
            find.byWidgetPredicate((w) => w is Text && w.data == '自定义预览ABC'),
          )
          .where((w) => w.style?.fontVariations?.isNotEmpty == true)
          .toList();
      expect(fontText, isNotEmpty);
      expect(fontText.map((w) => w.style!.color).toSet(), {
        const Color(0xff000000),
      });
      final weight = fontText.first.style!.fontVariations!
          .firstWhere((a) => a.axis == 'wght')
          .value;
      expect(weight, 500);
      for (int attempt = 0; attempt < 20; attempt++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump();
        if (File('${temp.path}/state.json').existsSync()) break;
      }
      final state = jsonDecode(
        File('${temp.path}/state.json').readAsStringSync(),
      );
      expect(state['sample'], '自定义预览ABC');
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      repo.root = null;
      repo.local = [];
      temp.deleteSync(recursive: true);
      expect(t.takeException(), isNull);
    },
  );
}
