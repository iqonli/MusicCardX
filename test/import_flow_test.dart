import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/main.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/song_search_page.dart';

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
  });
  testWidgets('plain external text opens share tab without JSON replacement', (
    t,
  ) async {
    var first = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          if (call.method == 'takeIncoming' && first) {
            first = false;
            return {
              'kind': 'json',
              'text': '分享《测试》 https://music.163.com/song?id=1',
            };
          }
          return null;
        });
    await t.pumpWidget(MusicCardX(CardDocument.fresh(), chinese));
    await t.pumpAndSettle();
    expect(find.text('替换当前歌曲信息？'), findsNothing);
    expect(find.text('来自音乐软件'), findsOneWidget);
    expect(find.text('解析'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is EditableText && w.controller.text.startsWith('分享《测试》'),
      ),
      findsOneWidget,
    );
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets('new shares replace an open search page through the home route', (
    t,
  ) async {
    final queue = Queue<Map<String, dynamic>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          if (call.method == 'takeIncoming') {
            return queue.isEmpty ? null : queue.removeFirst();
          }
          return null;
        });
    await t.pumpWidget(MusicCardX(CardDocument.fresh(), chinese));
    await t.pumpAndSettle();
    final dynamic editor = t.state(find.byType(Editor));
    unawaited(editor.searchSongInformation() as Future<void>);
    await t.pumpAndSettle();
    for (final text in ['第一个分享', '第二个分享']) {
      queue.add({'kind': 'json', 'text': text});
      unawaited(editor.incoming() as Future<void>);
      await t.pumpAndSettle();
      expect(find.byType(SongSearchPage, skipOffstage: false), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is EditableText && w.controller.text == text,
        ),
        findsOneWidget,
      );
      expect(editor.receiving, false);
    }
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byType(SongSearchPage, skipOffstage: false), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets('a share received during confirmation is handled after cancel', (
    t,
  ) async {
    final queue = Queue<Map<String, dynamic>>()
      ..add({'kind': 'json', 'text': '{"title":"first"}'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          if (call.method == 'takeIncoming') {
            return queue.isEmpty ? null : queue.removeFirst();
          }
          return null;
        });
    await t.pumpWidget(MusicCardX(CardDocument.fresh(), chinese));
    await t.pumpAndSettle();
    expect(find.text('替换当前歌曲信息？'), findsOneWidget);
    queue.add({'kind': 'json', 'text': '{"title":"second"}'});
    final dynamic editor = t.state(find.byType(Editor));
    unawaited(editor.incoming() as Future<void>);
    await t.pump();
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(find.text('替换当前歌曲信息？'), findsOneWidget);
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w is EditableText && w.controller.text == 'second',
      ),
      findsOneWidget,
    );
    expect(queue, isEmpty);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'external image confirmation previews the incoming cover and cancel preserves state',
    (t) async {
      final path = File('test/fixtures/audio/cover.png').absolute.path;
      var incoming = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, (call) async {
            if (call.method == 'takeIncoming' && incoming) {
              incoming = false;
              return {'kind': 'image', 'path': path};
            }
            return null;
          });
      final doc = CardDocument.fresh();
      await t.pumpWidget(MusicCardX(doc, chinese));
      await t.pumpAndSettle();
      expect(find.text('替换当前封面？'), findsOneWidget);
      final image = t.widget<Image>(find.byType(Image));
      expect(
        ((image.image as ResizeImage).imageProvider as FileImage).file.path,
        path,
      );
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(doc.text('coverPath'), '');
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'removing a cover requires confirmation and cancel preserves it',
    (t) async {
      final path = File('test/fixtures/audio/cover.png').absolute.path;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, (call) async => null);
      final doc = CardDocument.fresh()..data['coverPath'] = path;
      await t.pumpWidget(MusicCardX(doc, chinese));
      for (int n = 0; n < 20; n++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await t.pumpAndSettle();
        if (t
                .widget<TextButton>(find.widgetWithText(TextButton, '移除封面'))
                .onPressed !=
            null) {
          break;
        }
      }
      expect(
        t.widget<TextButton>(find.widgetWithText(TextButton, '移除封面')).onPressed,
        isNotNull,
        reason: 'Cover must be loaded before removal',
      );
      expect(find.text('选择图片 当前封面16×16'), findsOneWidget);
      await t.ensureVisible(find.text('移除封面'));
      await t.pumpAndSettle();
      await t.tap(find.text('移除封面'));
      await t.pumpAndSettle();
      expect(find.text('移除当前封面？'), findsOneWidget);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(doc.text('coverPath'), path);
      await t.tap(find.text('移除封面'));
      await t.pumpAndSettle();
      await t.tap(find.text('确定'));
      await t.pumpAndSettle();
      expect(doc.text('coverPath'), '');
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('a failed incoming item does not block the following item', (
    t,
  ) async {
    final queue = Queue<Map<String, dynamic>>()
      ..add({'kind': 'error', 'text': '读取失败'})
      ..add({'kind': 'json', 'text': '{"title":"valid"}'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          if (call.method == 'takeIncoming') {
            return queue.isEmpty ? null : queue.removeFirst();
          }
          return null;
        });
    await t.pumpWidget(MusicCardX(CardDocument.fresh(), chinese));
    await t.pumpAndSettle();
    expect(find.text('替换当前歌曲信息？'), findsOneWidget);
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w is EditableText && w.controller.text == 'valid',
      ),
      findsOneWidget,
    );
    expect(queue, isEmpty);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
