import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/seed.dart';
import 'package:musiccardx/palette_tools.dart';
import 'package:musiccardx/weight_dialog.dart';
import 'package:musiccardx/editor_pages.dart';
import 'package:musiccardx/cover_shape.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(CardDocument.initialize);
  test('original JS seed sequence matches unsigned 32-bit implementation', () {
    for (final seed in ['00000000', '32721283', '中文🎵']) {
      int h = 2166136261;
      for (final c in seed.codeUnits) {
        h = ((h ^ c) * 16777619) & 0xffffffff;
      }
      h ^= h >>> 13;
      h = (h * 0x5bd1e995) & 0xffffffff;
      h ^= h >>> 15;
      if (h == 0) h = 0x9e3779b9;
      final random = OriginalRandom(seed);
      for (int i = 0; i < 40; i++) {
        h = (h * 1664525 + 1013904223) & 0xffffffff;
        expect(random.nextDouble(), h / 4294967296);
      }
    }
  });
  test('title formatting quotes conditions arithmetic variables and multivalue tags', () {
    final tf = TitleFormat({
      'title': '0',
      'artist': ['A', 'B'],
      'tracknumber': '3',
    });
    expect(tf.evaluate(r'$if(%title%,yes,no)'), 'yes');
    expect(tf.evaluate(r'[literal]'), '');
    expect(tf.evaluate(r'[$upper(%title%)]'), '0');
    expect(tf.evaluate(r'$if(%missing%,$unknown(),ok)'), 'ok');
    expect(tf.evaluate(r'$ifequal($add(2,3),5,yes,no)'), 'yes');
    expect(tf.evaluate(r'$puts(x,$mul(4,5))$get(x)'), '20');
    expect(tf.evaluate(r'$meta_sep(artist, / )'), 'A / B');
    expect(tf.evaluate(r'$num(%tracknumber%,2)'), '03');
    expect(tf.evaluate(r"'['%title%']'"), '[0]');
    expect(tf.evaluate(r'$substr(abcdef,2,4)'), 'bcd');
  });
  test(
    'flood fill respects connected color region and mixes local average',
    () {
      final bytes = Uint8List.fromList([
        for (int y = 0; y < 4; y++)
          for (int x = 0; x < 8; x++) ...[
            x < 4 ? 220 : 20,
            0,
            x < 4 ? 0 : 220,
            255,
          ],
      ]);
      final pixels = CoverPixels(8, 4, bytes);
      final c = pixels.average(const Offset(.1, .5), 3, flood: true);
      expect(c.r, greaterThan(.8));
      expect(c.b, lessThan(.1));
    },
  );
  test('external song payload accepts JSON tags and plain text', () {
    expect(songFieldsFromText('{"fields":{"title":"A"}}')['title'], 'A');
    expect(songFieldsFromText('artist=B\ntitle=A')['artist'], 'B');
    expect(songFieldsFromText('Song title')['title'], 'Song title');
  });
  test('all quantizers produce five deterministic colors', () async {
    final p = CoverPixels(
      10,
      10,
      Uint8List.fromList([
        for (int i = 0; i < 100; i++) ...[
          i < 50 ? 255 : 0,
          i < 50 ? 0 : 255,
          0,
          255,
        ],
      ]),
    );
    for (final algo in paletteAlgorithms.keys) {
      final a = await p.palette(algo), b = await p.palette(algo);
      expect(a.length, 5);
      expect(a, b);
      expect(a.first.a, 1);
    }
  });
  test('cover shapes are finite and have consistent bounds', () {
    final doc = CardDocument.fresh();
    doc.data['coverCornerRadius'] = 30;
    for (final shape in [
      'round',
      'continuous',
      'bevel',
      'concave',
      'superellipse',
      'ellipse',
      'individual',
    ]) {
      doc.data['coverShape'] = shape;
      final path = coverShape(const Rect.fromLTWH(0, 0, 360, 360), doc);
      expect(path.getBounds().width, closeTo(360, .001));
      expect(path.getBounds().height, closeTo(360, .001));
      expect(path.contains(const Offset(180, 180)), true);
    }
  });
  testWidgets('variable weight supports direct entry and step buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WeightDialog(
            value: 400,
            min: 100,
            max: 900,
            variable: true,
            family: [],
            choices: [400, 700],
          ),
        ),
      ),
    );
    await tester.tap(find.text('+100'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '500',
    );
    await tester.enterText(find.byType(TextField), '650');
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 650);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('static weights show subfamily names', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WeightDialog(
            value: 400,
            min: 1,
            max: 1000,
            variable: false,
            family: [
              {
                'weight': 400,
                'subfamily': 'Regular',
                'fullName': 'Regular',
                'family': 'T',
                'fileName': 'r.ttf',
              },
              {
                'weight': 700,
                'subfamily': 'Bold',
                'fullName': 'Bold',
                'family': 'T',
                'fileName': 'b.ttf',
              },
            ],
            choices: [400, 700],
          ),
        ),
      ),
    );
    expect(find.text('400 Regular'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('song JSON dialog roundtrip and paste replaces content', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => call.method == 'Clipboard.getData'
              ? {'text': '{"title":"new"}'}
              : null,
        );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SongJsonPage(fields: {'title': 'old'})),
      ),
    );
    await tester.tap(find.text('粘贴'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '{\n  "title": "new"\n}',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
