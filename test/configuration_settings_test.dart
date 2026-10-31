import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/main.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChineseConverter chinese;
  setUpAll(() async {
    await CardDocument.initialize();
    chinese = ChineseConverter();
    await chinese.load();
  });
  testWidgets(
    'configuration snapshot and application include external font preferences and pinned state',
    (t) async {
      final directory = Directory.systemTemp.createTempSync('mcx-config-');
      final repo = FontRepository.instance;
      repo.root = directory;
      repo.mode = 'local';
      repo.tree = 'path:/shared/fonts';
      repo.sample = '保存我的预览文本';
      repo.previewSize = 88;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, (_) async => null);
      final d = CardDocument.fresh();
      d.data['previewPinned'] = false;
      d.data['imageFolder'] = '/pictures/current';
      await t.pumpWidget(MusicCardX(d, chinese));
      await t.pumpAndSettle();
      final dynamic editor = t.state(find.byType(Editor));
      final snapshot = Map<String, dynamic>.from(
        editor.configurationSnapshot() as Map,
      );
      expect(snapshot['fontPreferences'], {
        'mode': 'local',
        'tree': 'path:/shared/fonts',
        'sample': '保存我的预览文本',
        'previewSize': 88.0,
      });
      repo.tree = '';
      repo.sample = 'changed';
      repo.previewSize = 100;
      final next = CardDocument.fromJson(snapshot);
      editor.doc = next;
      var applied = false;
      final task =
          editor.applyConfigurationPreferences(snapshot) as Future<void>;
      task.then((_) {
        applied = true;
      });
      for (var i = 0; i < 30 && !applied; i++) {
        await t.pump();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(applied, isTrue);
      await task;
      await t.pumpAndSettle();
      expect(repo.sample, '保存我的预览文本');
      expect(repo.tree, 'path:/shared/fonts');
      expect(repo.previewSize, 88);
      expect(editor.pinned, false);
      expect(next.text('imageFolder'), '/pictures/current');
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, null);
      repo.root = null;
      directory.deleteSync(recursive: true);
    },
  );
}
