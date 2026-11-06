#include "shader_shared.hpp"
// v7 approved implementation, copied without modifying shader formulas.
namespace flow::detail {

V3 fusionSoft(State&st,V2 uv){V2 p=uv-V2(.5,.5);p.y*=st.height/st.width;
 double degree=perlin(V2(st.time*.11,p.x*p.y*2),st.seed);p=rot(p,(degree-.5)*TAU+PI);
 p.x+=std::sin(p.y*5+st.time*.75)/25.;p.y+=std::sin(p.x*7.5+st.time*.75)/12.5;
 p=warp(p*1.2,st.seed,st.time,.105);V3 c=bilinear(st.p[0],st.p[1],st.p[2],st.p[3],smooth(-.35,.32,rot(p,-.09).x),smooth(.37,-.45,p.y));
 V3 h=hsv(c);V2 w=uv-V2(.5,.5);double mo=std::sin(w.y*4+st.time*.34)+std::cos(w.x*3.5-st.time*.22);double wave=.5+.5*std::sin(mo+std::cos((w.x+w.y)*3.1)+st.time*.1);h.x=fract(h.x+.016*wave);h.y*=.91+.12*wave;h.z*=.89+.12*wave;
 return fromHSV(h);}

V3 fusionSoftV2Core(State&st,V2 uv,double foldStrength,double freq,double lightStrength){
 double aspect=st.width/st.height;
 V2 p=uv-V2(.5,.5);p.y/=aspect;
 double rotateNoise=perlin(V2(st.time*.09,p.x*p.y*2.),st.seed);
 p=rot(p,PI+(rotateNoise-.5)*TAU*(.38+.42*foldStrength));
 p.x+=std::sin(p.y*freq+st.time*.72)*(.015+.065*foldStrength);
 p.y+=std::sin(p.x*freq*1.4-st.time*.59)*(.02+.09*foldStrength);
 p=warp(p*1.2+V2(.3,-.2),st.seed,st.time,.15*foldStrength);
 double x=smooth(-.42,.36,rot(p,-.14).x),y=smooth(.48,-.42,p.y);
 V3 color=bilinear(st.p[0],st.p[1],st.p[2],st.p[3],x,y);
 // A coordinated wave: HSV value & saturation vary together but colors stay close to the palette.
 V2 w=uv-V2(.5,.5);
 double sine=std::sin(w.x*freq*.9+st.time*.24+2.*std::sin(w.y*2.2-st.time*.13));
 double fold=perlin(p*4.3+V2(st.time*.027,5.4),st.seed^0x665u);
 V3 h=hsv(color);
 h.x=fract(h.x+lightStrength*.010*sine);
 h.y=clamp(h.y*(1.-lightStrength*.17*(.5+.5*sine)));
 h.z=clamp(h.z*(1.-lightStrength*.24+lightStrength*.31*fold));
 return sat(fromHSV(h));
}

V3 fusionSoftV5(State&st,V2 uv){
 const double oldNewMix=st.k[0],freq=st.k[1],lightwave=st.k[2];
 const double swirl=st.k[3],colorBinding=st.k[4];
 // Level 1 in the OLD/new blend is exactly OLD when swirl and binding are zero.
 if(oldNewMix==0.&&swirl==0.&&colorBinding==0.)return fusionSoft(st,uv);
 V2 uv2=uv;
 if(swirl>0){
  V2 p=uv-V2(.5,.5);
  double a=swirl*.48*std::sin(3.5*length(p)+st.time*.034)
           +swirl*.31*(perlin(p*2.3+V2(2.5,st.time*.01),st.seed^0x89u)-.5);
  uv2=rot(p,a)+V2(.5,.5);
 }
 V3 old=fusionSoft(st,uv2);
 if(oldNewMix==0.&&colorBinding==0.)return old;
 V3 newer=fusionSoftV2Core(st,uv2,.6,freq,lightwave);
 V3 c=cmix(old,newer,oldNewMix);
 if(colorBinding>0.){
  double a=smooth(-.38,.42,uv2.x-.5),b=smooth(-.3,.5,uv2.y-.5);
  V3 constrained=bilinear(st.p[0],st.p[1],st.p[2],st.p[3],a,b);
  c=perceptual(c,constrained,colorBinding*.55);
 }
 return sat(c);
}

V3 shadeFusionSoft(State& st,V2 uv){return fusionSoftV5(st,uv);}
} // namespace flow::detail
