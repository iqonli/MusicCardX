import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/activity_catalog.dart';
import 'package:musiccardx/intent_actions.dart';
import 'package:musiccardx/song_search_page.dart';
import 'package:musiccardx/model.dart';
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();setUpAll(CardDocument.initialize);
 testWidgets('auto copy happens before launch and can be disabled',(t)async{
  final calls=<String>[];bool copy=true;
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(actionChannel,(c)async{calls.add(c.method);return null;});
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,(c)async{if(c.method=='Clipboard.setData')calls.add('copy');return null;});
  await t.pumpWidget(MaterialApp(home:Scaffold(body:StatefulBuilder(builder:(context,set)=>IntentActionsBar(actions:const [{'name':'执行','component':'com.example/.Ask','action':'test','parameters':'[]'}],prompt:()=> '内容',autoCopy:copy,onAutoCopy:(v)=>set(()=>copy=v),onSave:(_)async{})))));
  await t.tap(find.text('执行'));await t.pumpAndSettle();expect(calls,['copy','launchAction']);calls.clear();
  await t.tap(find.byType(Checkbox));await t.pumpAndSettle();await t.tap(find.text('执行'));await t.pumpAndSettle();expect(calls,['launchAction']);
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(actionChannel,null);t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,null);
 });
 test('catalog caches within session and clear forces new read',()async{
  ActivityCatalogCache.clear();int calls=0;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(actionChannel,(c)async{calls++;return [];});
  await ActivityCatalogCache.get();await ActivityCatalogCache.get();expect(calls,1);ActivityCatalogCache.clear();await ActivityCatalogCache.get();expect(calls,2);ActivityCatalogCache.clear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(actionChannel,null);
 });
 testWidgets('shortcut region hidden until prompt generated',(t)async{
  await t.pumpWidget(MaterialApp(home:SongSearchPage(document:CardDocument.fresh(),onSettings:()async{})));
  await t.tap(find.text('AI外包'));await t.pumpAndSettle();expect(find.byType(IntentActionsBar),findsNothing);
  await t.scrollUntilVisible(find.text('生成提示词'),250,scrollable:find.descendant(of:find.byType(ListView),matching:find.byType(Scrollable)).first);
  await t.tap(find.text('生成提示词'));await t.pumpAndSettle();expect(find.byType(IntentActionsBar),findsOneWidget);
  await t.pumpWidget(const SizedBox());await t.pumpAndSettle();
 });
}
