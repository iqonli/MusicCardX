import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:musiccardx/main.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/hex_text.dart';
import 'package:musiccardx/color_picker.dart';
import 'package:musiccardx/image_export.dart';

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
    'colour normalization changes only colour values and preserves cursor',
    () {
      final doc = CardDocument.fresh();
      doc.styles['titleValue']['colorHex'] = 'R%20+#ABCDEF';
      doc.data['customEnvironmentColors'] = [
        '#ABCDEF',
        '#AABBCC',
        '#FFFFFF',
        '#000000',
        '#FF0000',
      ];
      doc.data['customEnvironmentColorsEnabled'] = true;
      doc.fields['title'] = 'ABCDEF';
      doc.data['solidHex'] = '#AABBCC';
      doc.lyrics['dividerTopHex'] = '#FEDCBA';
      final normalized = CardDocument.fromJson(doc.data);
      expect(normalized.styles['titleValue']['colorHex'], 'r%20+#abcdef');
      expect(normalized.text('solidHex'), '#aabbcc');
      expect(normalized.lyrics['dividerTopHex'], '#fedcba');
      expect(normalized.fields['title'], 'ABCDEF');
      expect(normalized.data['customEnvironmentColors'].first, '#abcdef');
      const v = TextEditingValue(
        text: '#AbCdEf',
        selection: TextSelection.collapsed(offset: 4),
      );
      final lower = const LowerHexFormatter().formatEditUpdate(
        TextEditingValue.empty,
        v,
      );
      expect(lower.text, '#abcdef');
      expect(lower.selection, v.selection);
      expect(colorHex(const Color(0xffaabbcc)), '#aabbcc');
    },
  );
  test(
    'PNG/JPEG signatures, dimensions, alpha matte and quality are correct',
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 32, 32),
        Paint()..color = const Color(0xffff0000),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, 32);
      try {
        final png = await encodeExportImage(image, const ImageExportOptions());
        expect(png.bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        expect(png.mimeType, 'image/png');
        expect(img.decodePng(png.bytes)!.getPixel(60, 16).a, 0);
        final jpg = await encodeExportImage(
          image,
          const ImageExportOptions(format: 'jpg', quality: 95),
        );
        expect(jpg.bytes.take(3), [255, 216, 255]);
        expect(jpg.mimeType, 'image/jpeg');
        expect(jpg.extension, 'jpg');
        final decoded = img.decodeJpg(jpg.bytes)!;
        expect((decoded.width, decoded.height), (64, 32));
        expect(decoded.getPixel(12, 16).r, greaterThan(240));
        expect(decoded.getPixel(12, 16).g, lessThan(12));
        final white = decoded.getPixel(60, 16);
        expect(white.r, greaterThan(245));
        expect(white.g, greaterThan(245));
        final codec = await ui.instantiateImageCodec(jpg.bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 64);
        frame.image.dispose();
        codec.dispose();
      } finally {
        image.dispose();
        picture.dispose();
      }
      final noise = img.Image(width: 128, height: 96);
      for (final p in noise) {
        final n = (p.x * 3329 + p.y * 6553) & 255;
        p.setRgb(n, (n * 43) & 255, (n * 17) & 255);
      }
      final source = await ui.instantiateImageCodec(img.encodePng(noise));
      final frame = await source.getNextFrame();
      try {
        final low = await encodeExportImage(
          frame.image,
          const ImageExportOptions(format: 'jpg', quality: 15),
        );
        final high = await encodeExportImage(
          frame.image,
          const ImageExportOptions(format: 'jpg', quality: 95),
        );
        expect(low.bytes.length, lessThan(high.bytes.length));
      } finally {
        frame.image.dispose();
        source.dispose();
      }
    },
  );
  testWidgets(
    'compression settings persist without rerender and all output paths use JPG metadata',
    (t) async {
      final calls = <MethodCall>[];
      final folder = (await t.runAsync(
        () => Directory.systemTemp.createTemp('mcx-export-'),
      ))!;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, (c) async {
            calls.add(c);
            return null;
          });
      final doc = CardDocument.fresh()..data['imageFolder'] = folder.path;
      await t.pumpWidget(MusicCardX(doc, chinese));
      await t.pumpAndSettle();
      final dynamic editor = t.state(find.byType(Editor));
      final preview = editor.rendered.image;
      await t.tap(find.text('设置'));
      await t.pumpAndSettle();
      expect(
        t.getTopLeft(find.text('图片压缩')).dy,
        lessThan(t.getTopLeft(find.text('保存图片文件夹')).dy),
      );
      await t.ensureVisible(find.text('图片压缩'));
      await t.tap(find.text('图片压缩'));
      await t.pumpAndSettle();
      expect(find.byType(Slider), findsNothing);
      await t.tap(find.text('JPG'));
      await t.pumpAndSettle();
      expect(find.byType(Slider), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('jpeg-quality')));
      await t.enterText(find.byKey(const ValueKey('jpeg-quality')), '82');
      await t.tap(find.text('确定'));
      await t.pumpAndSettle();
      expect(doc.text('imageFormat'), 'jpg');
      expect(doc.n('jpegQuality'), 82);
      expect(editor.rendered.image, same(preview));
      final restored = CardDocument.fromJson(doc.data);
      expect(restored.n('jpegQuality'), 82);
      for (final action in ['shareImage', 'copyImage', 'saveImage']) {
        await t.runAsync(() => editor.export(action) as Future<void>);
        await t.pumpAndSettle();
      }
      for (final action in ['shareImage', 'copyImage']) {
        final c = calls.lastWhere((c) => c.method == action);
        expect(c.arguments['mime'], 'image/jpeg');
        expect(c.arguments['name'], endsWith('.jpg'));
        expect((c.arguments['bytes'] as List).take(3), [255, 216, 255]);
      }
      final files = folder.listSync().whereType<File>().toList();
      expect(files.single.path, endsWith('.jpg'));
      expect(
        calls.lastWhere((c) => c.method == 'scanImage').arguments['mime'],
        'image/jpeg',
      );
      expect(editor.rendered.image, same(preview));
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await t.runAsync(() => folder.delete(recursive: true));
    },
  );
  testWidgets(
    'seed row is transparent and compact input paint retains standard touch target',
    (t) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, (_) async => null);
      await t.pumpWidget(MusicCardX(CardDocument.fresh(), chinese));
      await t.pumpAndSettle();
      for (final label in ['Input', '博览会']) {
        final button = find.widgetWithText(TextButton, label);
        expect(
          TextButtonTheme.of(t.element(button)).style!.backgroundColor!
              .resolve({}),
          Colors.transparent,
        );
      }
      expect(
        find.ancestor(of: find.text('从音频文件读取'), matching: find.byType(Card)),
        findsOneWidget,
      );
      final button = find.widgetWithText(TextButton, '选择图片');
      final style = TextButtonTheme.of(t.element(button)).style!;
      expect(style.minimumSize!.resolve({}), const Size(34, 34));
      expect(t.getSize(button).height, greaterThanOrEqualTo(48));
      expect(style.backgroundColor!.resolve({}), defaultControlColor);
      expect(style.elevation!.resolve({}), 0);
      final about = find.text('关于');
      await t.tap(find.text('设置'));
      await t.pumpAndSettle();
      expect(
        find.ancestor(of: about, matching: find.byType(Card)),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
}
