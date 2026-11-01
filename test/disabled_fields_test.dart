import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/disabled_song_fields_dialog.dart';
import 'package:musiccardx/editor_pages.dart';
import 'package:musiccardx/main.dart';
import 'package:musiccardx/metadata_prompt.dart';
import 'package:musiccardx/model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChineseConverter chinese;
  setUpAll(() async {
    await CardDocument.initialize();
    chinese = ChineseConverter();
    await chinese.load();
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  test('disabled tags are removed, persisted, and cannot return through config or new imports', () {
    final d = CardDocument.fresh();
    d.data['disabledSongFields'] = ['artist', 'tracknumber', 'bad'];
    d.data['fields'] = {
      'title': '保留',
      'artist': '删除',
      'tracknumber': '7',
      'custom': '扩展标签',
    };
    final roundtrip = CardDocument.fromJson(deepCopy(d.data));
    expect(roundtrip.disabledSongFields, {'artist', 'tracknumber'});
    expect(roundtrip.fields, {'title': '保留', 'custom': '扩展标签'});
    roundtrip.data['fields'] = {
      'title': '新歌曲',
      'artist': '粘贴值',
      'tracknumber': '1',
    };
    expect(roundtrip.fields, {'title': '新歌曲'});
    expect(roundtrip.cleanSongFields({'ARTIST': '不允许', 'album': '保留专辑'}), {
      'album': '保留专辑',
    });
    expect(metadataPrompt({'title': '测试'}), isNot(contains('\n\n')));
  });
  testWidgets(
    'nine disabled choices keep active checkboxes with gray struck labels',
    (t) async {
      t.view.physicalSize = const Size(800, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final initial = <String>{};
      Set<String>? result;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<Set<String>>(
                    context: context,
                    builder: (_) => DisabledSongFieldsDialog(initial: initial),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('打开'));
      await t.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNWidgets(9));
      await t.tap(find.text('艺术家'));
      await t.pumpAndSettle();
      final text = t.widget<Text>(find.text('艺术家'));
      expect(text.style!.decoration, TextDecoration.lineThrough);
      expect(text.style!.color, Colors.grey);
      final tile = t.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, '艺术家'),
      );
      expect(tile.value, true);
      expect(tile.onChanged, isNotNull);
      expect(initial, isEmpty);
      await t.tap(find.text('保存'));
      await t.pumpAndSettle();
      expect(result, {'artist'});
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'input disables selected field and JSON paste strips it before applying',
    (t) async {
      final d = CardDocument.fresh();
      d.data['disabledSongFields'] = ['artist'];
      d.fields['title'] = '原标题';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, (call) async => null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async => call.method == 'Clipboard.getData'
                ? {'text': '{"title":"新标题","artist":"必须删除"}'}
                : null,
          );
      await t.pumpWidget(MusicCardX(d, chinese));
      await t.pumpAndSettle();
      final input = t.widget<TextFormField>(
        find.ancestor(
          of: find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == '艺术家',
          ),
          matching: find.byType(TextFormField),
        ),
      );
      expect(input.enabled, false);
      expect(input.initialValue, '已禁用');
      expect(d.fields.containsKey('artist'), false);
      final dynamic editor = t.state(find.byType(Editor));
      unawaited(editor.songJson() as Future<void>);
      await t.pumpAndSettle();
      await t.tap(find.text('粘贴'));
      await t.pumpAndSettle();
      final json = t
          .widget<TextField>(
            find.descendant(
              of: find.byType(SongJsonPage),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text;
      expect(jsonDecode(json), {'title': '新标题'});
      await t.tap(find.text('确定'));
      await t.pumpAndSettle();
      expect(editor.doc.fields, {'title': '新标题'});
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('clear all confirms and removes tags cover and lyrics together', (
    t,
  ) async {
    final d = CardDocument.fresh();
    d.lyrics['text'] = '保留的歌词';
    d.fields['title'] = '原歌曲';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async => null);
    await t.pumpWidget(MusicCardX(d, chinese));
    await t.pumpAndSettle();
    final dynamic editor = t.state(find.byType(Editor));
    editor.doc.data['coverPath'] = 'old-cover.jpg';
    unawaited(editor.clearSongCoverLyrics() as Future<void>);
    await t.pumpAndSettle();
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(editor.doc.fields['title'], '原歌曲');
    expect(editor.doc.lyrics['text'], '保留的歌词');
    expect(editor.doc.text('coverPath'), 'old-cover.jpg');
    unawaited(editor.clearSongCoverLyrics() as Future<void>);
    await t.pumpAndSettle();
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    expect(editor.doc.fields, isEmpty);
    expect(editor.doc.lyrics['text'], '');
    expect(editor.doc.text('coverPath'), '');
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
