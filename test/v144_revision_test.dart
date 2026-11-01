import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/cover_search.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/song_search.dart';
import 'package:musiccardx/song_search_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(CardDocument.initialize);
  test('share defaults preserve best matches and follow selected album', () {
    SongCandidate candidate(
      String id,
      double score,
      Map<String, String> fields,
    ) => SongCandidate(
      CoverCandidate(
        source: 'test',
        id: id,
        title: fields['title']!,
        artist: fields['artist']!,
        album: fields['album']!,
        artwork: '',
        score: score,
      ),
      fields,
    );
    final results = [
      candidate('a', 95, {
        'title': '同一标题',
        'artist': '新艺术家',
        'album': '新专辑',
        'date': '2026',
        'tracknumber': '3',
        'totaltracks': '10',
      }),
      candidate('b', 80, {
        'title': '另一标题',
        'artist': '另一艺术家',
        'album': '旧专辑',
        'date': '2000',
        'tracknumber': '8',
        'totaltracks': '12',
      }),
    ];
    final defaults = defaultShareSelection(results, {
      'title': '同一标题',
      'artist': '原艺术家',
      'album': '旧专辑',
      'date': '2000',
      'tracknumber': '8',
    });
    expect(defaults.containsKey('title'), false);
    expect(defaults['artist'], '新艺术家');
    expect(defaults['album'], '新专辑');
    expect(defaults['date'], '2026');
    expect(defaults['tracknumber'], '3');
    expect(defaults['totaltracks'], '10');
    expect(defaults.containsKey('discnumber'), false);
    expect(defaultShareSelection([], {'title': '保留'}), isEmpty);
  });

  for (final tab in ['传统爬爬', 'AI外包', '来自音乐软件']) {
    testWidgets('$tab touch outside drops text focus immediately', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: SongSearchPage(
            document: CardDocument.fresh(),
            onSettings: () async {},
          ),
        ),
      );
      await t.tap(find.text(tab));
      await t.pumpAndSettle();
      final field = find.byType(EditableText).first;
      await t.tap(field);
      await t.pump();
      expect(t.widget<EditableText>(field).focusNode.hasFocus, true);
      final gesture = await t.startGesture(const Offset(3, 280));
      await t.pump();
      expect(t.widget<EditableText>(field).focusNode.hasFocus, false);
      await gesture.up();
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'generated prompt actions align at top and helper precedes editor',
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
      expect(
        t.getTopLeft(find.text('编辑歌曲信息JSON')).dy,
        closeTo(t.getTopLeft(find.text('复制')).dy, 1),
      );
      expect(
        t.getTopLeft(find.text('编辑歌曲信息JSON')).dx,
        greaterThan(t.getTopLeft(find.text('复制')).dx),
      );
      final top = t.getTopLeft(find.byType(ListView)).dy;
      expect(
        t.getTopLeft(find.text('生成提示词')).dy,
        inInclusiveRange(top, top + 40),
      );
      final helper = find.text('复制并发给你的AI，请开启联网搜索，复制AI的回答再回到此处，使用下面的按钮粘贴');
      final prompt = find.byWidgetPredicate(
        (w) => w is TextField && w.controller!.text.startsWith('你是一个音乐元数据补全助手'),
      );
      expect(t.getTopLeft(helper).dy, lessThan(t.getTopLeft(prompt).dy));
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('share help is an inline text hyperlink', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: SongSearchPage(
          document: CardDocument.fresh(),
          onSettings: () async {},
          initialShareText: '',
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('此处 查看详细内容'), findsNothing);
    final rich = t.widget<Text>(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.textSpan?.toPlainText().startsWith('在音乐软件中点击分享') ?? false),
      ),
    );
    final children = (rich.textSpan as TextSpan).children!.cast<TextSpan>();
    final link = children.firstWhere((s) => s.text == '点击此处');
    expect(link.style!.decoration, TextDecoration.underline);
    (link.recognizer as TapGestureRecognizer).onTap!();
    await t.pumpAndSettle();
    expect(find.text('支持的解析链接'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
