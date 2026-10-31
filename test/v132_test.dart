import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/main.dart';
import 'package:musiccardx/cover_shape.dart';
import 'package:musiccardx/cover_shape_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChineseConverter chinese;
  setUpAll(() async {
    await CardDocument.initialize();
    chinese = ChineseConverter();
    await chinese.load();
  });
  testWidgets('cover shape choices and parameters stay inside one dialog', (
    t,
  ) async {
    final doc = CardDocument.fresh();
    var changes = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoverShapeDialog(document: doc, onChanged: () => changes++),
        ),
      ),
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(CoverShapeIcon), findsNWidgets(10));
    expect(find.byType(DropdownButton<String>), findsNothing);
    await t.tap(find.text('独立四角'));
    await t.pump();
    expect(find.byType(TextFormField), findsNWidgets(4));
    for (final label in ['↖', '↗', '↙', '↘']) {
      expect(find.text(label), findsOneWidget);
    }
    final tl = find.byKey(const ValueKey('individual:cornerTL'));
    await t.tap(tl);
    await t.enterText(tl, '24');
    await t.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      (doc.data['coverShapeParameters'] as Map)['individual']['cornerTL'],
      24,
    );
    await t.tap(find.text('普通圆角'));
    await t.pump();
    final radius = find.byKey(const ValueKey('round:coverCornerRadius'));
    await t.enterText(radius, '18');
    await t.pump();
    expect(
      (doc.data['coverShapeParameters'] as Map)['round']['coverCornerRadius'],
      18,
    );
    await t.tap(find.text('独立四角'));
    await t.pump();
    expect(t.widget<TextFormField>(tl).controller!.text, '24');
    expect(changes, greaterThanOrEqualTo(4));
    await t.pumpWidget(const SizedBox());
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'large image inertia follows Android clamping and stops on contact',
    (t) async {
      final controller = PhotoViewController(initialScale: 1);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhotoView.customChild(
              controller: controller,
              childSize: const Size(4000, 4000),
              initialScale: 1.0,
              minScale: 1.0,
              maxScale: 8.0,
              child: const ColoredBox(color: Colors.red),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final dynamic core = t.state(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == 'PhotoViewCore',
        ),
      );
      core.onScaleStart(ScaleStartDetails(focalPoint: const Offset(400, 300)));
      core.onScaleEnd(
        ScaleEndDetails(
          velocity: const Velocity(pixelsPerSecond: Offset(2000, 0)),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      final expected = ClampingScrollSimulation(
        position: 0,
        velocity: 2000,
      ).x(.1);
      expect(controller.position.dx, closeTo(expected, 1));
      expect(controller.position.dy, closeTo(0, .01));
      final previous = controller.position;
      final finger = await t.startGesture(const Offset(400, 300));
      await t.pump(const Duration(milliseconds: 100));
      expect(controller.position, previous);
      await finger.up();
      await t.pumpWidget(const SizedBox());
      controller.dispose();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('input buttons have standard targets and bottom tabs are 56dp', (
    t,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async => null);
    final doc = CardDocument.fresh();
    await t.pumpWidget(MusicCardX(doc, chinese));
    await t.pumpAndSettle();
    expect(
      t.getSize(find.byKey(const ValueKey('bottom-tabs'))).height,
      kBottomNavigationBarHeight,
    );
    for (final label in ['选择图片', '保存封面', '移除封面', '从音频文件读取', '清空歌词内容']) {
      final button = find.widgetWithText(TextButton, label);
      expect(t.getSize(button).height, greaterThanOrEqualTo(48), reason: label);
      final style = TextButtonTheme.of(t.element(button)).style!;
      expect(style.textStyle!.resolve({})!.fontSize, 13);
    }
    await t.tap(find.text('工作台'));
    await t.pumpAndSettle();
    final auto = find.text('自动黑白色');
    await t.ensureVisible(auto);
    await t.pumpAndSettle();
    final row = t.widget<Row>(
      find.ancestor(of: auto, matching: find.byType(Row)).first,
    );
    expect(row.children.first, isA<Flexible>());
    expect(
      t.widget<Text>(auto).style?.color,
      isNot(Theme.of(t.element(auto)).colorScheme.primary),
    );
    await t.tap(auto);
    await t.pumpAndSettle();
    expect(doc.text('autoColorMode'), 'black');
    expect(
      t.widget<Text>(find.text('锁黑色')).style!.color,
      Theme.of(t.element(auto)).colorScheme.primary,
    );
    await t.tap(auto);
    await t.pumpAndSettle();
    expect(doc.text('autoColorMode'), 'white');
    expect(find.text('锁白色'), findsOneWidget);
    await t.tap(auto);
    await t.pumpAndSettle();
    expect(doc.text('autoColorMode'), 'auto');
    expect(find.text('锁白色'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null);
  });
}
