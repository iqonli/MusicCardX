import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/song_search_page.dart';
import 'package:musiccardx/shortcut_flow.dart';
import 'package:musiccardx/intent_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(CardDocument.initialize);
  testWidgets(
    'prompt size changes only by button and generation scrolls to JSON anchor',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: SongSearchPage(
            document: CardDocument.fresh(),
            onSettings: () async {},
          ),
        ),
      );
      await t.tap(find.text('AI外包'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('生成提示词'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.tap(find.text('生成提示词'));
      await t.pumpAndSettle();
      final top = t.getTopLeft(find.byType(ListView)).dy;
      expect(
        t.getTopLeft(find.text('编辑歌曲信息JSON')).dy,
        inInclusiveRange(top, top + 40),
      );
      final field = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '生成的提示词',
      );
      expect(t.widget<TextField>(field).maxLines, 1);
      expect(
        t.getTopLeft(field).dy,
        greaterThan(t.getBottomLeft(find.byType(IntentActionsBar)).dy),
      );
      expect(
        t.getTopLeft(find.textContaining('将搜索歌曲信息的任务外包')).dy,
        greaterThan(t.getBottomLeft(field).dy),
      );
      t.widget<TextField>(field).focusNode!.requestFocus();
      await t.pumpAndSettle();
      expect(t.widget<TextField>(field).maxLines, 1);
      await t.ensureVisible(find.byTooltip('放大'));
      await t.tap(find.byTooltip('放大'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(field).minLines, 10);
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      expect(t.widget<TextField>(field).minLines, 10);
      await t.ensureVisible(find.byTooltip('缩小'));
      await t.tap(find.byTooltip('缩小'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(field).maxLines, 1);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'flow one row when fitting otherwise two rows keeping final pair',
    (t) async {
      Future<void> draw(double width) async {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ShortcutFlow(
                  viewportWidth: width,
                  keepLastPair: true,
                  children: [
                    for (final n in ['A', 'B', '新建+', '管理'])
                      SizedBox(
                        key: ValueKey(n),
                        width: 70,
                        height: 40,
                        child: Text(n),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await t.pump();
      }

      await draw(400);
      expect(
        t.getTopLeft(find.byKey(const ValueKey('A'))).dy,
        t.getTopLeft(find.byKey(const ValueKey('管理'))).dy,
      );
      await draw(160);
      expect(
        t.getTopLeft(find.byKey(const ValueKey('新建+'))).dy,
        t.getTopLeft(find.byKey(const ValueKey('管理'))).dy,
      );
      expect(
        t.getTopLeft(find.byKey(const ValueKey('新建+'))).dy,
        greaterThan(t.getTopLeft(find.byKey(const ValueKey('A'))).dy),
      );
      expect(
        t.getTopLeft(find.byKey(const ValueKey('新建+'))).dx,
        lessThan(t.getTopLeft(find.byKey(const ValueKey('管理'))).dx),
      );
    },
  );
  testWidgets('long press saved shortcut opens editor without launch', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IntentActionsBar(
            actions: const [
              {
                'name': '快捷',
                'component': 'com.example/.A',
                'action': 'test',
                'parameters': '[]',
              },
            ],
            prompt: () => '',
            onSave: (_) async {},
          ),
        ),
      ),
    );
    await t.longPress(find.text('快捷'));
    await t.pumpAndSettle();
    expect(find.text('编辑调用'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
}
