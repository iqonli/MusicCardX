import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/metadata_prompt.dart';
import 'package:musiccardx/song_search_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(CardDocument.initialize);
  test('template placeholders and escaping survive persistence', () {
    final d = CardDocument.fresh();
    d.data['metadataPromptTemplate'] = '%filled% {{filled_fields_json}}';
    final restored = CardDocument.fromJson(d.data);
    expect(
      restored.data['metadataPromptTemplate'],
      '%filled% {{filled_fields_json}}',
    );
    final p = metadataPrompt({'title': 'A"B'}, template: '%filled%');
    expect(p, contains(r'A\"B'));
    expect(defaultMetadataPromptTemplate, contains(r'双引号写为 \"'));
    expect(defaultMetadataPromptTemplate, isNot(contains('\n\n')));
  });
  testWidgets('prompt border follows inputs and regeneration', (t) async {
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
    expect(find.byIcon(Icons.settings), findsOneWidget);
    final input = t
        .widgetList<TextField>(find.byType(TextField))
        .first
        .controller!;
    await t.scrollUntilVisible(
      find.text('生成提示词'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await t.tap(find.text('生成提示词'));
    await t.pumpAndSettle();
    TextField editor() => t.widget<TextField>(
      find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == '生成的提示词'),
    );
    final old = input.text;
    input.text = 'changed';
    await t.pump();
    expect(editor().decoration!.enabledBorder!.borderSide.color, Colors.red);
    input.text = old;
    await t.pump();
    expect(editor().decoration!.enabledBorder, isNull);
    input.text = 'again';
    await t.pump();
    await t.tap(find.text('生成提示词'));
    await t.pumpAndSettle();
    expect(editor().decoration!.enabledBorder, isNull);
    await t.tap(find.text('来自音乐软件'));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.public), findsNothing);
    expect(find.byIcon(Icons.settings), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
}
