import 'dart:async';

import 'package:musiccardx/activity_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/intent_actions.dart';

void main() {
  testWidgets(
    'catalog reports activity progress and keeps loading-time search',
    (t) async {
      final loaded = Completer<List<Map<String, dynamic>>>();
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(actionChannel, (
        c,
      ) async {
        if (c.method == 'catalogLoad') return loaded.future;
        if (c.method == 'catalogProgress') return {'loaded': 3, 'total': 10};
        return null;
      });
      await t.pumpWidget(const MaterialApp(home: ActivityCatalogPage()));
      await t.enterText(find.byType(TextField), '示例');
      await t.pump(const Duration(milliseconds: 250));
      await t.pump();
      expect(find.text('3/10'), findsOneWidget);
      loaded.complete([
        {'name': '示例应用', 'package': 'com.example', 'activities': <dynamic>[]},
      ]);
      await t.pumpAndSettle();
      expect(find.text('示例应用'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        actionChannel,
        null,
      );
    },
  );
  testWidgets('advanced settings folded and tests use dedicated text', (
    t,
  ) async {
    Map? sent;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(actionChannel, (
      call,
    ) async {
      if (call.method == 'actionPermissions') return <String>[];
      if (call.method == 'launchAction') sent = call.arguments as Map;
      return null;
    });
    await t.pumpWidget(
      MaterialApp(
        home: IntentActionEditor(
          initial: const {'name': 'test', 'component': 'com.example/.Ask'},
          prompt: () => '真实提示词',
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('详细设置 不建议编辑'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Action'), findsNothing);
    expect(find.text('这是一段测试提示词，爱来自MusicCardX'), findsOneWidget);
    await t.tap(find.text('测试'));
    await t.pumpAndSettle();
    expect((sent!['extras'] as List).first['value'], '这是一段测试提示词，爱来自MusicCardX');
    await t.tap(find.text('详细设置 不建议编辑'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Action'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      actionChannel,
      null,
    );
  });
}
