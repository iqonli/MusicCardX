import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/dialog_buttons.dart';
import 'package:musiccardx/main.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/color_picker.dart';
import 'package:musiccardx/weight_dialog.dart';
import 'package:musiccardx/cover_shape_dialog.dart';
import 'package:musiccardx/editor_pages.dart';
import 'package:musiccardx/image_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(CardDocument.initialize);
  void transparentActions(WidgetTester t, Finder scope) {
    final buttons = find.descendant(
      of: scope,
      matching: find.byType(TextButton),
    );
    expect(buttons, findsWidgets);
    for (final element in buttons.evaluate()) {
      final button = element.widget as TextButton;
      if (element.findAncestorWidgetOfExactType<SegmentedButton<String>>() !=
          null) {
        continue;
      }
      for (final states in [
        <WidgetState>{},
        {WidgetState.disabled},
      ]) {
        final color =
            button.style?.backgroundColor?.resolve(states) ??
            TextButtonTheme.of(element).style?.backgroundColor?.resolve(states);
        expect(color, Colors.transparent);
      }
    }
  }

  for (final kind in ['颜色', '字重', '圆角', 'JSON', '压缩']) {
    testWidgets('$kind dialog actions have no page-button fill', (t) async {
      Widget dialog() => switch (kind) {
        '颜色' => const CardColorDialog(value: '#2196f3'),
        '字重' => const WeightDialog(
          value: 400,
          min: 100,
          max: 900,
          variable: true,
          family: [],
          choices: [400, 700],
        ),
        '圆角' => CoverShapeDialog(
          document: CardDocument.fresh(),
          onChanged: () {},
        ),
        'JSON' => const SongJsonPage(fields: {'title': 'Title'}),
        _ => const ImageCompressionDialog(initial: ImageExportOptions()),
      };
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(backgroundColor: defaultControlColor),
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showCardDialog<void>(
                  context: context,
                  builder: (_) => dialog(),
                ),
                child: const Text('页面按钮'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('页面按钮'));
      await t.pumpAndSettle();
      transparentActions(t, find.byType(AlertDialog));
      if (kind == '颜色') expect(find.text('#2196f3'), findsOneWidget);
      if (kind == '字重') expect(find.text('+100'), findsOneWidget);
      final context = t.element(find.byType(AlertDialog));
      Navigator.pop(context);
      await t.pumpAndSettle();
      expect(
        TextButtonTheme.of(t.element(find.text('页面按钮'))).style!.backgroundColor!
            .resolve({}),
        defaultControlColor,
      );
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'nested dialogs remain transparent and restore page styles after close',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(backgroundColor: defaultControlColor),
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showCardDialog<void>(
                  context: context,
                  builder: (outer) => AlertDialog(
                    actions: [
                      TextButton(
                        onPressed: () => showCardDialog<void>(
                          context: outer,
                          builder: (inner) => AlertDialog(
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(inner),
                                child: const Text('关闭内层'),
                              ),
                            ],
                          ),
                        ),
                        child: const Text('嵌套'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(outer),
                        child: const Text('关闭外层'),
                      ),
                    ],
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('打开'));
      await t.pumpAndSettle();
      await t.tap(find.text('嵌套'));
      await t.pumpAndSettle();
      transparentActions(t, find.byType(AlertDialog).last);
      await t.tap(find.text('关闭内层'));
      await t.pumpAndSettle();
      transparentActions(t, find.byType(AlertDialog));
      await t.tap(find.text('关闭外层'));
      await t.pumpAndSettle();
      expect(
        TextButtonTheme.of(t.element(find.text('打开'))).style!.backgroundColor!
            .resolve({}),
        defaultControlColor,
      );
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    },
  );
}
