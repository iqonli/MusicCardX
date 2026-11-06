import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'cover_preparation.dart';
export 'cover_preparation.dart' show prepareMistCover;
const parameterRanges = <String, List<(String, double, double)>>{
  'mist': [
    ('texture_mix', 0, .10),
    ('warp_strength', 0, .20),
    ('field_size', .50, .75),
    ('detail_suppression', 0, 1),
    ('palette_softness', .55, 1.45),
  ],
  'fusionSoft': [
    ('old_new_mix', 0, .80),
    ('flow_frequency', 3, 7),
    ('lightwave_strength', 0, .50),
    ('swirl_strength', 0, 1),
    ('color_binding', 0, .80),
  ],
  'fusionHard': [
    ('old_new_mix', 0, 1),
    ('nonperiodic_warp', 0, .48),
    ('transition_softness', .60, 1.40),
    ('accent_weight', 0, 1),
    ('large_scale_mix', 0, 1),
  ],
  'lightFlow': [('warp_strength',0,1.2),('ridge_strength',0,.72),('ridge_frequency',2,10)],
};
typedef _RenderNative = Int32 Function(Int32,Pointer<Uint8>,IntPtr,Double,Double,Int32,Int32,Pointer<Uint32>,Pointer<Uint8>,Pointer<Uint8>,Int32,Int32,Pointer<Uint8>,IntPtr,Int32);
typedef _RenderDart = int Function(int,Pointer<Uint8>,int,double,double,int,int,Pointer<Uint32>,Pointer<Uint8>,Pointer<Uint8>,int,int,Pointer<Uint8>,int,int);
class _Native {
 final DynamicLibrary library;
 _Native():library=_open();
 static DynamicLibrary _open(){
  final path=Platform.environment['MCX_BACKGROUND_LIBRARY'];
  if(path!=null)return DynamicLibrary.open(path);
  if(Platform.isIOS||Platform.isMacOS)return DynamicLibrary.process();
  return DynamicLibrary.open(Platform.isWindows?'mcx_background.dll':'libmcx_background.so');
 }
 late final alloc=library.lookupFunction<Pointer<Void> Function(IntPtr),Pointer<Void> Function(int)>('mcx_alloc');
 late final release=library.lookupFunction<Void Function(Pointer<Void>),void Function(Pointer<Void>)>('mcx_free');
 late final render=library.lookupFunction<_RenderNative,_RenderDart>('mcx_render');
}
final _native=_Native();
Map<String,Object> renderSeedBackground(Map<String,Object?> args){
 final mode=args['mode'] as String,index=['fusionSoft','fusionHard','lightFlow','mist'].indexOf(args['mode'] as String);
 if(index<0)throw ArgumentError.value(mode,'mode');
 final width=args['width'] as double,height=args['height'] as double;
 if(!width.isFinite||!height.isFinite||width<=0||height<=0)throw ArgumentError('Invalid dimensions');
 final factor=660/max(width,height),w=max(1,(width*min(1,factor)).round()),h=max(1,(height*min(1,factor)).round());
 final palette=args['palette'] as List<int>;
 if(palette.length!=5)throw ArgumentError('Five colors required');
 final seed=utf8.encode(args['seed'] as String);
 Map<String,Object>? prepared=args['preparedCover'] as Map<String,Object>?;
 if(mode=='mist'&&prepared==null&&args['cover']!=null)prepared=prepareMistCover(args);
 final allocations=<Pointer<Void>>[];
 Pointer<T> allocate<T extends NativeType>(int size){final p=_native.alloc(max(1,size));if(p==nullptr)throw StateError('Allocation failed');allocations.add(p);return p.cast<T>();}
 try{
  final text=allocate<Uint8>(seed.length);text.asTypedList(seed.length).setAll(0,seed);
  final colors=allocate<Uint32>(20);colors.asTypedList(5).setAll(0,palette);
  Pointer<Uint8> first=nullptr,second=nullptr;int tw=0,th=0;
  if(mode=='mist'&&prepared!=null){
   tw=prepared['width'] as int;th=prepared['height'] as int;final a=prepared['blur1'] as Uint8List,b=prepared['blur2'] as Uint8List;
   if(tw<1||th<1||tw>512||th>512||a.length!=tw*th*4||b.length!=a.length)throw ArgumentError('Invalid artwork');
   first=allocate<Uint8>(a.length);second=allocate<Uint8>(b.length);first.asTypedList(a.length).setAll(0,a);second.asTypedList(b.length).setAll(0,b);
  }
  final size=w*h*4,output=allocate<Uint8>(w*h*4);
  final code=_native.render(index,text,seed.length,width,height,w,h,colors,first,second,tw,th,output,size,(args['threads'] as int?)??0);
  if(code!=0)throw StateError('Native renderer failed ($code)');
  return {'bytes':Uint8List.fromList(output.asTypedList(size)),'width':w,'height':h};
 }finally{for(final p in allocations.reversed){_native.release(p);}}
}
