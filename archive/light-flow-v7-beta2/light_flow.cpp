#include "shader_shared.hpp"
// v7 approved implementation, copied without modifying shader formulas.
namespace flow::detail {

V3 lightFlow(State&st,V2 uv){V2 p=uv-V2(.5,.5);double aspect=st.width/st.height;p.y/=aspect;double angle=(perlin(V2(st.time*.1,p.x*p.y),st.seed)-.5)*TAU+PI;p=rot(p,angle);p.y*=aspect;
 p.x+=std::sin(p.y*5.+st.time*2.)/30.;p.y+=std::sin(p.x*7.5+st.time*2.)/15.;
 double x=smooth(-.3,.2,rot(p,-.0873).x);double y=smooth(.5,-.3,p.y);V3 v=bilinear(st.p[0],st.p[1],st.p[2],st.p[3],x,y);
 double fine=fbm(p*3.5+V2(st.time*.08,0),st.seed^0x789f,3);
 return cmix(v,st.p[4],.11*smooth(.45,.8,fine));}

V3 lightFlowV5(State&st,V2 uv){
 const double flowGain=st.k[0],microRidge=st.k[1],paletteFog=st.k[2];
 const double ridgeWidth=st.k[3],ridgeContrast=st.k[4];
 if(flowGain==1. && microRidge==0. && paletteFog==.11)return lightFlow(st,uv);
 V2 p=uv-V2(.5,.5);double aspect=st.width/st.height;p.y/=aspect;
 double angle=(perlin(V2(st.time*.1,p.x*p.y),st.seed)-.5)*TAU+PI;
 p=rot(p,angle);p.y*=aspect;
 p.x+=(std::sin(p.y*5.+st.time*2.)/30.)*flowGain;
 p.y+=(std::sin(p.x*7.5+st.time*2.)/15.)*flowGain;
 double x=smooth(-.3,.2,rot(p,-.0873).x),y=smooth(.5,-.3,p.y);
 V3 c=bilinear(st.p[0],st.p[1],st.p[2],st.p[3],x,y);
 double fine=fbm(p*3.5+V2(st.time*.08,0),st.seed^0x789f,3);
 c=cmix(c,st.p[4],paletteFog*smooth(.45,.8,fine));
 if(microRidge>0){
  double q=p.x*.73+p.y*.68;
  double v=std::sin(5.5*q+.72*std::sin(p.y*2.9+st.time*.045));
  double ridge=std::exp(-12.*v*v/(ridgeWidth*ridgeWidth));
  c+=V3{1,1,1}*(microRidge*ridgeContrast*ridge);
 }
 return sat(c);
}

V3 shadeLightFlow(State& st,V2 uv){return lightFlowV5(st,uv);}
} // namespace flow::detail
