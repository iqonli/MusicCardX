#include "shader_shared.hpp"
#include <cstdlib>
#include <future>
#include <thread>
#if defined(_WIN32)
#define MCX_API extern "C" __declspec(dllexport)
#else
#define MCX_API extern "C" __attribute__((visibility("default"),used))
#endif
MCX_API void* mcx_alloc(size_t n){return std::malloc(n);}
MCX_API void mcx_free(void* p){std::free(p);}
MCX_API int mcx_render(int mode,const uint8_t* seed,size_t length,double width,double height,int w,int h,
 const uint32_t* colors,const uint8_t* first,const uint8_t* second,int tw,int th,uint8_t* out,size_t capacity,int threads){
 try{
  if(mode<0||mode>3||!seed||!colors||!out||!std::isfinite(width)||!std::isfinite(height)||width<=0||height<=0||w<1||h<1||w>660||h>660||capacity<size_t(w)*h*4)return -1;
  if((first||second)&&(!first||!second||tw<1||th<1||tw>512||th>512))return -2;
  using namespace flow;using namespace flow::detail;
  State st;st.width=width;st.height=height;std::string text(reinterpret_cast<const char*>(seed),length);st.seed=seedHash(text);st.time=double(st.seed%30000)/197.;
  const char* modes[]={"fusionSoft","fusionHard","lightFlow","mist"};st.c.effect=modes[mode];st.k=seedV7Parameters(st.c.effect,text);
  for(int i=0;i<5;i++)st.p[i]=satAdjust(V3{double((colors[i]>>16)&255)/255.,double((colors[i]>>8)&255)/255.,double(colors[i]&255)/255.},1.12);
  auto load=[&](const uint8_t* bytes){Texture t;if(bytes){t.w=tw;t.h=th;t.a.resize(size_t(tw)*th);for(size_t i=0;i<t.a.size();i++)t.a[i]={bytes[i*4]/255.,bytes[i*4+1]/255.,bytes[i*4+2]/255.};}return t;};st.blur1=load(first);st.blur2=load(second);
  V3(*shade)(State&,V2)=mode==0?shadeFusionSoft:mode==1?shadeFusionHard:mode==2?shadeLightFlow:shadeMist;
  auto job=[&](int lo,int hi){for(int y=lo;y<hi;y++)for(int x=0;x<w;x++){
   V3 c=sat(shade(st,V2{(x+.5)/w,(y+.5)/h}));double d=(rnd(uint32_t(x)*374761393u^uint32_t(y)*668265263u^st.seed)-.5)/255.;size_t i=(size_t(y)*w+x)*4;
   out[i]=uint8_t(clamp(c.x+d)*255+.5);out[i+1]=uint8_t(clamp(c.y+d)*255+.5);out[i+2]=uint8_t(clamp(c.z+d)*255+.5);out[i+3]=255;
  }};
  int n=std::max(1,std::min({threads>0?threads:int(std::thread::hardware_concurrency()),8,h}));std::vector<std::future<void>> workers;
  for(int i=1;i<n;i++)workers.emplace_back(std::async(std::launch::async,job,i*h/n,(i+1)*h/n));job(0,h/n);for(auto& f:workers)f.get();return 0;
 }catch(...){return -9;}
}
