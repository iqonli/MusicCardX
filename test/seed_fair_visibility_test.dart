import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/main.dart';
import 'package:musiccardx/model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChineseConverter chinese;
  setUpAll(() async {
    await CardDocument.initialize();
    chinese = ChineseConverter();
    await chinese.load();
  });
  testWidgets('seed fair button is visible only for fusion backgrounds', (
    t,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (_) async => null);
    final doc = CardDocument.fresh();
    await t.pumpWidget(MusicCardX(doc, chinese));
    await t.pumpAndSettle();
    final dynamic editor = t.state(find.byType(Editor));
    for (final mode in backgrounds.keys) {
      doc.setBackground(mode);
      editor.changed();
      await t.pumpAndSettle();
      expect(
        find.text('博览会'),
        seededBackgrounds.contains(mode) ? findsOneWidget : findsNothing,
        reason: mode,
      );
      expect(find.text('Input'), findsOneWidget);
      expect(find.textContaining('Copy seed:'), findsOneWidget);
    }
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'solid mode adds a colour picker directly after the background button',
    (t) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, (_) async => null);
      t.view.physicalSize = const Size(1100, 960);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final doc = CardDocument.fresh();
      await t.pumpWidget(MusicCardX(doc, chinese));
      await t.pumpAndSettle();
      await t.tap(find.text('工作台'));
      await t.pumpAndSettle();
      expect(find.text('自定义'), findsNothing);
      doc.data['backgroundStyle'] = 'solid';
      final dynamic editor = t.state(find.byType(Editor));
      editor.changed();
      await t.pumpAndSettle();
      final custom = find.text('自定义');
      expect(custom, findsOneWidget);
      expect(
        t.getTopLeft(custom).dy,
        closeTo(t.getTopLeft(find.text('背景')).dy, 2),
      );
      expect(
        t.getTopLeft(custom).dx,
        greaterThan(t.getTopLeft(find.text('背景')).dx),
      );
      await t.tap(custom);
      await t.pumpAndSettle();
      final hex = find.byType(TextFormField).last;
      await t.enterText(hex, 'r%10+#12AB34');
      await t.tap(find.text('确定'));
      await t.pumpAndSettle();
      expect(doc.text('solidHex'), 'r%10+#12ab34');
      doc.data['backgroundStyle'] = 'ink';
      editor.changed();
      await t.pumpAndSettle();
      expect(find.text('自定义'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, null);
      expect(t.takeException(), isNull);
    },
  );
}
