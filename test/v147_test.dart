import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/intent_actions.dart';
import 'package:musiccardx/model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(CardDocument.initialize);
  final action = {
    'name': 'test',
    'component': 'com.example/.Ask',
    'action': 'android.intent.action.PROCESS_TEXT',
    'mime': 'text/plain',
    'parameters':
        '[{"key":"text","type":"charSequence","value":"prefix {{prompt}}"}]',
  };
  test('typed extras interpolate without parsing prompt as JSON', () {
    expect(
      (prepareAction(action, 'a"\nb')['extras'] as List).first['value'],
      'prefix a"\nb',
    );
    expect(
      () => prepareAction({
        ...action,
        'parameters': '[{"key":"flag","type":"boolean","value":"yes"}]',
      }, ''),
      throwsFormatException,
    );
    expect(
      () => prepareAction({...action, 'component': 'invalid'}, ''),
      throwsFormatException,
    );
  });
  test('action configurations survive configuration import', () {
    final d = CardDocument.fresh();
    d.data['intentActions'] = [action];
    expect(CardDocument.fromJson(d.data).data['intentActions'], [action]);
  });
  testWidgets('empty bar has only new and saved bar offers manage', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IntentActionsBar(
            actions: const [],
            prompt: () => '',
            onSave: (_) async {},
          ),
        ),
      ),
    );
    expect(find.text('新建+'), findsOneWidget);
    expect(find.text('管理'), findsNothing);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IntentActionsBar(
            actions: [action],
            prompt: () => '',
            onSave: (_) async {},
          ),
        ),
      ),
    );
    expect(find.text('管理'), findsOneWidget);
    expect(find.text('test'), findsOneWidget);
  });
}
