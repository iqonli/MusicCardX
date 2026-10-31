import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/main.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/fonts.dart';

void main() {
  late ChineseConverter chinese;
  setUpAll(() async {
    await CardDocument.initialize();
    chinese = ChineseConverter();
    await chinese.load();
  });
  testWidgets('first preview waits for font repository initialization', (
    t,
  ) async {
    final directory = Directory.systemTemp.createTempSync('mcx-font-start-');
    Directory('${directory.path}/fonts-flutter').createSync();
    File(
      '${directory.path}/fonts-flutter/state.json',
    ).writeAsStringSync('{"sample":"loaded first","mode":"local","local":[]}');
    final gate = Completer<String>();
    final repo = FontRepository.instance;
    repo.root = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          platform,
          (c) async => c.method == 'storageRoot' ? gate.future : null,
        );
    await t.pumpWidget(MusicCardX(CardDocument.fresh(), chinese));
    await t.pump(const Duration(seconds: 1));
    final dynamic state = t.state(find.byType(Editor));
    expect(state.rendered, isNull);
    gate.complete(directory.path);
    for (var i = 0; i < 80 && state.rendered == null; i++) {
      await t.pump(const Duration(milliseconds: 20));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(repo.sample, 'loaded first');
    expect(state.rendered, isNotNull);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    repo.root = null;
    directory.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null);
  });
}
