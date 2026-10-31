import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/main.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/export_filename.dart';
import 'package:musiccardx/cover_shape.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChineseConverter chinese;
  setUpAll(() async {
    await CardDocument.initialize();
    chinese = ChineseConverter();
    await chinese.load();
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null),
  );
  test(
    'filename optional fields, seed visibility, sanitizing and UTF8 limit',
    () {
      final d = CardDocument.fresh();
      d.fields.addAll({'title': 'Song', 'artist': 'Singer', 'album': 'Album'});
      d.data['seed'] = '12345678';
      d.data['backgroundStyle'] = 'fusion';
      expect(
        exportFilename(d, 'png'),
        'MusicCardX-Song-Singer-Album-12345678.png',
      );
      d.data['backgroundStyle'] = 'solid';
      expect(exportFilename(d, 'jpg'), 'MusicCardX-Song-Singer-Album-.jpg');
      d.fields.clear();
      expect(exportFilename(d, 'png'), 'MusicCardX-.png');
      expect(exportFilename(d, 'png', expression: 'a/b:c?d'), 'a_b_c_d.png');
      expect(exportFilename(d, 'png', expression: ''), 'MusicCardX.png');
      expect(
        utf8.encode(exportFilename(d, 'png', expression: '中' * 200)).length,
        lessThanOrEqualTo(184),
      );
      expect(exportFilename(d, 'png', expression: r'$upper(test)'), 'TEST.png');
    },
  );
  test('new shapes remain bounded and survive strict configuration import', () {
    for (final type in ['elliptical', 'quadratic', 'scoop']) {
      final d = CardDocument.fresh();
      d.data['coverShape'] = type;
      d.data['coverShapeParameters'] = {
        type: {
          'coverCornerRadius': 40,
          'cornerRadiusX': 55,
          'cornerRadiusY': 20,
          'cornerTension': .4,
        },
      };
      final restored = CardDocument.fromJson(d.data);
      expect(restored.text('coverShape'), type);
      expect(restored.data['coverShapeParameters'][type]['cornerRadiusX'], 55);
      final path = coverShape(const Rect.fromLTWH(5, 8, 180, 140), restored);
      expect(path.contains(const Offset(95, 78)), isTrue);
      expect(path.contains(const Offset(5, 8)), isFalse);
      final b = path.getBounds();
      expect(b.left, greaterThanOrEqualTo(4.99));
      expect(b.right, lessThanOrEqualTo(185.01));
      expect(b.top, greaterThanOrEqualTo(7.99));
      expect(b.bottom, lessThanOrEqualTo(148.01));
    }
  });
  testWidgets('typing saves draft without rendering until focus leaves', (
    t,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (_) async => null);
    final d = CardDocument.fresh();
    await t.pumpWidget(MusicCardX(d, chinese));
    await t.pumpAndSettle();
    final dynamic editor = t.state(find.byType(Editor));
    final old = editor.rendered;
    final title = find.byKey(ValueKey('field-title-${d.hashCode}'));
    await t.enterText(title, 'Draft title');
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(d.fields['title'], 'Draft title');
    expect(identical(editor.rendered, old), isTrue);
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    expect(identical(editor.rendered, old), isFalse);
    expect(editor.renderedRevision, editor.revision);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
  testWidgets('crop position dialog slider and number stay in sync', (t) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (_) async => null);
    final d = CardDocument.fresh();
    await t.pumpWidget(MusicCardX(d, chinese));
    await t.pumpAndSettle();
    final dynamic editor = t.state(find.byType(Editor));
    final future = editor.editText(
      '背景截取封面位置 %',
      '50',
      numeric: true,
      slider: true,
    );
    await t.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
    await t.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      ),
      '75',
    );
    await t.pump();
    expect(t.widget<Slider>(find.byType(Slider)).value, 75);
    t.widget<Slider>(find.byType(Slider)).onChanged!(25);
    await t.pump();
    expect(find.text('25.0'), findsOneWidget);
    await t.tap(find.text('保存'));
    await t.pumpAndSettle();
    expect(await future, '25.0');
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
  testWidgets('filename dialog previews editing without saving on cancel', (
    t,
  ) async {
    final d = CardDocument.fresh();
    d.fields['title'] = 'Example';
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (_) => FilenameDialog(document: d),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '[%title%]-%seed%');
    await t.pump();
    expect(find.text('Example-${d.text('seed')}.png'), findsOneWidget);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(d.text('imageFilename'), defaultImageFilename);
  });
}
