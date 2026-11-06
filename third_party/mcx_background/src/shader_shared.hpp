#pragma once
// FlowBench4 Seed v7: shared shader and color math, directly extracted from v7.
// These inline helpers allow each algorithm to be compiled as an independent .cpp.
#include "flowbench.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>
namespace flow::detail {
constexpr double PI=3.14159265358979323846, TAU=2*PI;
inline double clamp(double x,double lo=0,double hi=1){return std::max(lo,std::min(hi,x));}
inline double fract(double x){return x-std::floor(x);}
inline double mix(double a,double b,double t){return a+(b-a)*t;}
inline double smooth(double a,double b,double x){double t=clamp((x-a)/(b-a));return t*t*(3-2*t);}
inline double swave(double x){return std::sin(x);}
struct V2 {double x=0,y=0;V2()=default;V2(double a,double b):x(a),y(b){}V2 operator+(V2 v)const{return {x+v.x,y+v.y};} V2 operator-(V2 v)const{return {x-v.x,y-v.y};} V2 operator*(double f)const{return {x*f,y*f};} V2 operator/(double f)const{return {x/f,y/f};}};
struct V3 {double x=0,y=0,z=0;V3()=default;V3(double a,double b,double c):x(a),y(b),z(c){}V3 operator+(V3 v)const{return {x+v.x,y+v.y,z+v.z};} V3 operator-(V3 v)const{return{x-v.x,y-v.y,z-v.z};} V3 operator*(double f)const{return{x*f,y*f,z*f};} V3 operator/(double f)const{return{x/f,y/f,z/f};} V3& operator+=(V3 v){x+=v.x;y+=v.y;z+=v.z;return *this;}};
inline V2 operator*(double f,V2 v){return v*f;}
inline V3 operator*(double f,V3 v){return v*f;}
inline double dot(V2 a,V2 b){return a.x*b.x+a.y*b.y;}
inline double length(V2 a){return std::sqrt(dot(a,a));}
inline double dot(V3 a,V3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
inline V3 norm(V3 v){double d=std::sqrt(dot(v,v));return d>1e-10?v/d:V3{};}
inline V2 rot(V2 p,double angle){double s=std::sin(angle),c=std::cos(angle);return {p.x*c-p.y*s,p.x*s+p.y*c};}
inline V3 cmix(V3 a,V3 b,double f){return a+(b-a)*f;}
inline V3 sat(V3 c){return{clamp(c.x),clamp(c.y),clamp(c.z)};}
inline V3 from(Color c){return{c.r,c.g,c.b};}
inline Color toColor(V3 c){return{c.x,c.y,c.z};}
inline V3 mul(V3 a,V3 b){return{a.x*b.x,a.y*b.y,a.z*b.z};}
inline double luma(V3 c){return .2126*c.x+.7152*c.y+.0722*c.z;}
inline uint32_t hash32(uint32_t v){v^=v>>16;v*=0x7feb352du;v^=v>>15;v*=0x846ca68bu;v^=v>>16;return v;}
inline double rnd(uint32_t x){return (hash32(x)>>8)*(1./16777216.);}
inline double hash21(V2 p,uint32_t salt=0){int x=int(std::floor(p.x)),y=int(std::floor(p.y));return rnd(uint32_t(x)*0x9e3779b9u^uint32_t(y)*0x85ebca6bu^salt);}
inline double valueNoise(V2 p,uint32_t s=0){V2 i{std::floor(p.x),std::floor(p.y)},f{fract(p.x),fract(p.y)};f={f.x*f.x*(3-2*f.x),f.y*f.y*(3-2*f.y)};return mix(mix(hash21(i,s),hash21(i+V2(1,0),s),f.x),mix(hash21(i+V2(0,1),s),hash21(i+V2(1,1),s),f.x),f.y);}
inline V2 grad2(V2 p,uint32_t s){double a=hash21(p,s)*TAU;return{std::cos(a),std::sin(a)};}
inline double perlin(V2 p,uint32_t s){V2 i{std::floor(p.x),std::floor(p.y)},f{fract(p.x),fract(p.y)};double u=f.x*f.x*(3-2*f.x),v=f.y*f.y*(3-2*f.y);double a=dot(grad2(i,s),f),b=dot(grad2(i+V2(1,0),s),f-V2(1,0));double c=dot(grad2(i+V2(0,1),s),f-V2(0,1)),d=dot(grad2(i+V2(1,1),s),f-V2(1,1));return .5+.5*mix(mix(a,b,u),mix(c,d,u),v)*1.4142;}
inline double fbm(V2 p,uint32_t s,int oct=4){double sum=0,a=.54,norm=0;for(int k=0;k<oct;k++){sum+=a*valueNoise(p,s+k*0x9e37);norm+=a;p=rot(p*2.08,.5);a*=.5;}return sum/std::max(.001,norm);}
inline double noise3(V3 p,uint32_t s){int X=int(std::floor(p.x)),Y=int(std::floor(p.y)),Z=int(std::floor(p.z));double x=fract(p.x),y=fract(p.y),z=fract(p.z);x=x*x*(3-2*x);y=y*y*(3-2*y);z=z*z*(3-2*z);auto h=[&](int dx,int dy,int dz){return rnd(hash32(uint32_t(X+dx)*0x9e3779b9u^uint32_t(Y+dy)*0x85ebca6bu^uint32_t(Z+dz)*0xc2b2ae35u^s));};return mix(mix(mix(h(0,0,0),h(1,0,0),x),mix(h(0,1,0),h(1,1,0),x),y),mix(mix(h(0,0,1),h(1,0,1),x),mix(h(0,1,1),h(1,1,1),x),y),z);}
inline V2 warp(V2 p,uint32_t s,double time,double amount=.16){V2 off{fbm(p*2.5+V2(time*.17,3),s,4),fbm(p*2.5+V2(8,-time*.13),s+54,4)};return p+(off-V2(.5,.5))*2*amount;}
inline double srgbDecode(double v){return v<=.04045?v/12.92:std::pow((v+.055)/1.055,2.4);}
inline double srgbEncode(double v){v=clamp(v);return v<=.0031308?v*12.92:1.055*std::pow(v,1./2.4)-.055;}
inline V3 oklab(V3 c){double r=srgbDecode(c.x),g=srgbDecode(c.y),b=srgbDecode(c.z);
 double l=std::pow(.4122214708*r+.5363325363*g+.0514459929*b,1.0/3.0),m=std::pow(.2119034982*r+.6806995451*g+.1073969566*b,1.0/3.0),s=std::pow(.0883024619*r+.2817188376*g+.6299787005*b,1.0/3.0);
 return{.2104542553*l+.7936177850*m-.0040720468*s,1.9779984951*l-2.4285922050*m+.4505937099*s,.0259040371*l+.7827717662*m-.8086757660*s};}
inline V3 fromOklab(V3 c){double l=c.x+.3963377774*c.y+.2158037573*c.z,m=c.x-.1055613458*c.y-.0638541728*c.z,s=c.x-.0894841775*c.y-1.2914855480*c.z;l=l*l*l;m=m*m*m;s=s*s*s;return{srgbEncode(4.0767416621*l-3.3077115913*m+.2309699292*s),srgbEncode(-1.2684380046*l+2.6097574011*m-.3413193965*s),srgbEncode(-.0041960863*l-.7034186147*m+1.7076147010*s)};}
inline V3 perceptual(V3 a,V3 b,double t){return fromOklab(cmix(oklab(a),oklab(b),clamp(t)));}
// Precompute Oklab endpoints outside the pixel loop for palette-space bilinear interpolation.
inline V3 bilinear(V3 a,V3 b,V3 c,V3 d,double x,double y){return cmix(cmix(a,b,clamp(x)),cmix(c,d,clamp(x)),clamp(y));}
inline V3 hsv(V3 rgb){double mx=std::max({rgb.x,rgb.y,rgb.z}),mn=std::min({rgb.x,rgb.y,rgb.z}),dt=mx-mn;double h=0;if(dt>1e-7){if(mx==rgb.x)h=std::fmod((rgb.y-rgb.z)/dt+6,6.)/6;else if(mx==rgb.y)h=((rgb.z-rgb.x)/dt+2)/6;else h=((rgb.x-rgb.y)/dt+4)/6;}return{h,mx>0?dt/mx:0,mx};}
inline V3 fromHSV(V3 h){double x=fract(h.x)*6.;int i=int(x);double f=x-i;double p=h.z*(1-h.y),q=h.z*(1-f*h.y),t=h.z*(1-(1-f)*h.y);switch(i%6){case 0:return{h.z,t,p};case 1:return{q,h.z,p};case 2:return{p,h.z,t};case 3:return{p,q,h.z};case 4:return{t,p,h.z};default:return{h.z,p,q};}}
inline V3 aces(V3 c){auto m=[](double x){return clamp((x*(2.51*x+.03))/(x*(2.43*x+.59)+.14));};return{m(c.x),m(c.y),m(c.z)};}
struct Texture {int w=0,h=0;std::vector<V3> a;};
inline Texture texture(const Image&im){Texture t;t.w=im.width;t.h=im.height;t.a.resize(size_t(t.w)*t.h);for(size_t i=0;i<t.a.size();i++)t.a[i]={im.rgba[i*4]/255.,im.rgba[i*4+1]/255.,im.rgba[i*4+2]/255.};return t;}
inline V3 tex(const Texture&t,V2 uv){if(t.w<2||t.h<2)return{.35,.35,.35};double x=clamp(uv.x)*(t.w-1),y=clamp(uv.y)*(t.h-1);int xi=int(x),yi=int(y),x1=std::min(xi+1,t.w-1),y1=std::min(yi+1,t.h-1);double fx=x-xi,fy=y-yi;return bilinear(t.a[size_t(yi)*t.w+xi],t.a[size_t(yi)*t.w+x1],t.a[size_t(y1)*t.w+xi],t.a[size_t(y1)*t.w+x1],fx,fy);}
inline Texture scaled(const Texture&t,int maxside){if(std::max(t.w,t.h)<=maxside)return t;int w=std::max(1,int(std::round(double(t.w)*maxside/std::max(t.w,t.h)))),h=std::max(1,int(std::round(double(t.h)*maxside/std::max(t.w,t.h))));Texture result;result.w=w;result.h=h;result.a.resize(size_t(w)*h);for(int y=0;y<h;y++)for(int x=0;x<w;x++)result.a[size_t(y)*w+x]=tex(t,{(x+.5)/w,(y+.5)/h});return result;}
inline Texture boxblur(Texture t,int rad){if(rad<=0)return t;Texture out=t;std::vector<V3> tmp=t.a;int w=t.w,h=t.h;
for(int y=0;y<h;y++){V3 sum{};int ct=0;for(int k=-rad;k<=rad;k++){int v=std::clamp(k,0,w-1);sum+=t.a[size_t(y)*w+v];ct++;}for(int x=0;x<w;x++){tmp[size_t(y)*w+x]=sum/double(ct);sum+=t.a[size_t(y)*w+std::clamp(x+rad+1,0,w-1)];sum+=t.a[size_t(y)*w+std::clamp(x-rad,0,w-1)]*(-1);}}
for(int x=0;x<w;x++){V3 sum{};int ct=0;for(int k=-rad;k<=rad;k++){int v=std::clamp(k,0,h-1);sum+=tmp[size_t(v)*w+x];ct++;}for(int y=0;y<h;y++){out.a[size_t(y)*w+x]=sum/double(ct);sum+=tmp[size_t(std::clamp(y+rad+1,0,h-1))*w+x];sum+=tmp[size_t(std::clamp(y-rad,0,h-1))*w+x]*(-1);}}
return out;}
inline V3 satAdjust(V3 c,double factor){V3 lab=oklab(sat(c));lab.y*=factor;lab.z*=factor;return fromOklab(lab);}
struct State {
 double width=1,height=1;Config c;uint32_t seed=0;double time=0;std::array<V3,5> p{};
 std::array<double,5> k{};
 Texture cover,blur1,blur2;
};

// Public shader entry points implemented in four separate translation units.
V3 shadeMist(State& st,V2 uv);
V3 shadeFusionHard(State& st,V2 uv);
V3 shadeFusionSoft(State& st,V2 uv);
V3 shadeLightFlow(State& st,V2 uv);
} // namespace flow::detail
