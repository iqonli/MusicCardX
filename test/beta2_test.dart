import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/inline_preview.dart';
import 'package:musiccardx/activity_catalog.dart';
import 'package:musiccardx/intent_actions.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('overflow preview only hits within original container',(t)async{
    final recorder=ui.PictureRecorder();Canvas(recorder).drawRect(const Rect.fromLTWH(0,0,20,20),Paint()..color=Colors.blue);
    final picture=recorder.endRecording();final image=await t.runAsync(()=>picture.toImage(20,20));
    int previews=0,buttons=0;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:Stack(clipBehavior:Clip.none,children:[
      Positioned(left:20,top:20,width:200,height:100,child:InlinePreview(image:image!,onTap:()=>previews++)),
      Positioned(left:250,top:150,child:TextButton(onPressed:()=>buttons++,child:const Text('其他按钮'))),
    ]))));
    final dynamic state=t.state(find.byType(InlinePreview));state.transform(const Offset(100,50),const Offset(100,50),4.0);await t.pump();
    final box=t.renderObject<RenderBox>(find.byType(PreviewHitBoundary));
    expect(box.hitTest(BoxHitTestResult(),position:const Offset(100,120)),false);
    await t.tapAt(const Offset(100,60));await t.pump();expect(previews,1);
    await t.tapAt(const Offset(100,200));await t.pump();expect(previews,1);
    await t.tap(find.text('其他按钮'));await t.pump();expect(buttons,1);expect(previews,1);
    await t.pumpWidget(const SizedBox());image.dispose();picture.dispose();
  });
  testWidgets('catalog expands lazily copies class and returns component',(t)async{
    int queries=0;String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(actionChannel,(c)async{
      if(c.method=='catalogLoad')return [{'name':'示例应用','package':'com.example','activities':[{'name':'询问','className':'com.example.Ask','component':'com.example/com.example.Ask','enabled':true,'exported':true,'callable':true,'permission':''}]}];
      if(c.method=='catalogIcon')return null;
      if(c.method=='catalogActivities'){queries++;return [{'name':'询问','className':'com.example.Ask','component':'com.example/com.example.Ask','enabled':true,'exported':true,'callable':true,'permission':''}];}
      return [];
    });
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,(c)async{if(c.method=='Clipboard.setData')copied=(c.arguments as Map)['text'];return null;});
    Map<String,dynamic>? picked;
    await t.pumpWidget(MaterialApp(home:Builder(builder:(ctx)=>Scaffold(body:TextButton(onPressed:()async{picked=await Navigator.push<Map<String,dynamic>>(ctx,MaterialPageRoute(builder:(_)=>const ActivityCatalogPage()));},child:const Text('打开'))))));
    await t.tap(find.text('打开'));await t.pumpAndSettle();expect(queries,0);
    await t.tap(find.text('示例应用'));await t.pumpAndSettle();expect(queries,0);
    await t.tap(find.byTooltip('复制活动名称'));await t.pumpAndSettle();expect(copied,'com.example.Ask');
    await t.tap(find.text('询问'));await t.pumpAndSettle();expect(picked,isNull);await t.tap(find.text('填入“目标Activity”'));await t.pumpAndSettle();expect(picked?['component'],'com.example/com.example.Ask');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(actionChannel,null);
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,null);
  });
}
