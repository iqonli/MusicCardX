import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:musiccardx/model.dart';
import 'package:musiccardx/renderer.dart';
import 'package:musiccardx/seed_backgrounds.dart' as fast;
import 'background150_reference.dart' as old;
import 'renderer150_reference.dart' as reference;
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUpAll(CardDocument.initialize);
 test('pixel equality across seeds palettes ratios and artwork',(){
  final palettes=[[0xffb84150,0xff226a9c,0xffeed7a1,0xff1c3944,0xff8664a0],List.filled(5,0xff808080),[0xff000000,0xffffffff,0xffff0000,0xff00ff00,0xff0000ff]];
  final cover=Uint8List(64*48*4);for(var i=0;i<cover.length;i++){cover[i]=(i*37)%256;}
  var count=0;
  for(final mode in fast.parameterRanges.keys){for(var i=0;i<12;i++){
   final a=<String,Object?>{'mode':mode,'seed':['00000001','32721283','测试seed01','0'][i%4],'width':[96.0,48.0,1200.0][i%3],'height':[32.0,96.0,400.0][i%3],'palette':palettes[i%3]};
   if(mode=='mist'&&i%2==0)a.addAll({'cover':cover,'coverWidth':64,'coverHeight':48});
   final expected=old.renderSeedBackground(a),actual=fast.renderSeedBackground(a);
   expect(actual['width'],expected['width']);expect(actual['height'],expected['height']);expect(actual['bytes'],orderedEquals(expected['bytes'] as List),reason:'$mode/$i');count++;
   if(a['cover']!=null){final prepared=fast.prepareMistCover(a);expect(fast.renderSeedBackground({...a,'preparedCover':prepared})['bytes'],orderedEquals(expected['bytes'] as List));}
  }}print('$count complete RGBA images exactly equal');
 });
 test('full card equality and cache invalidation',() async {
  final a=CardRenderer(ChineseConverter(),FontRegistry());final b=reference.CardRenderer(ChineseConverter(),FontRegistry());
  final recorder=ui.PictureRecorder();final canvas=ui.Canvas(recorder);canvas.drawColor(const ui.Color(0xffa04060),ui.BlendMode.src);final picture=recorder.endRecording();final cover=await picture.toImage(32,32);picture.dispose();
  try{for(final mode in newBackgrounds){
   final d=CardDocument.fresh()..setBackground(mode);d.data['customEnvironmentColorsEnabled']=true;d.data['customEnvironmentColors']=['#b84150','#226a9c','#eed7a1','#1c3944','#8664a0'];
   for(var i=0;i<6;i++){
    if(i==1)d.fields['title']='缓存命中';if(i==2)d.data['seed']='新的种子';if(i==3){d.data['blurStrength']=30;d.data['customEnvironmentColors'][0]='#102030';}
    final out=await a.render(d,cover:i==4?null:cover,scaleOverride:[.2,.2,.5,1.0,1.0,2.0][i]),expected=await b.render(d,cover:i==4?null:cover,scaleOverride:[.2,.2,.5,1.0,1.0,2.0][i]);
    expect(await out.png(),orderedEquals(await expected.png()),reason:'$mode state $i');out.image.dispose();expected.image.dispose();
   }
  }}finally{a.clearBackgroundCache();cover.dispose();}
 },timeout: const Timeout(Duration(minutes:3)));
}
