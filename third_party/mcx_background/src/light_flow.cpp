#include "shader_shared.hpp"
// Ribbon field directly taken from the v4 screening package (V2 engine).
namespace flow::detail {
V3 lightFlowRibbon(State&st,V2 uv){
 const double warpStrength=st.k[0],ridgeStrength=st.k[1],ridgeFreq=st.k[2];
 double aspect=st.width/st.height;
 V2 p=uv-V2(.5,.5);p.y/=aspect;
 double angle=(perlin(V2(st.time*.09,p.x*p.y+2),st.seed)-.5)*TAU+PI;
 p=rot(p,angle);
 p.x+=std::sin(p.y*5.+st.time*1.8)*(.017+.04*warpStrength);
 p.y+=std::sin(p.x*7.5-st.time*1.2)*(.017+.06*warpStrength);
 p=warp(p*1.2,st.seed^0x55b5u,st.time,.16*warpStrength);
 double a=smooth(-.38,.33,rot(p,-.0873).x);
 double b=smooth(.49,-.38,p.y*aspect);
 V3 base=bilinear(st.p[0],st.p[1],st.p[2],st.p[3],a,b);
 double q=p.x*.68+p.y*.74;
 double slosh=std::sin(ridgeFreq*q + 1.7*std::sin(p.y*2.6+st.time*.045) + .9*std::sin(p.x*3.1-st.time*.034));
 double ribbon=std::exp(-14.*slosh*slosh);
 double haze=fbm(p*2.8+V2(st.time*.018,3),st.seed^0x383u,4);
 V3 mixed=perceptual(base,st.p[4],.12+.22*smooth(.38,.75,haze));
 return sat(mixed+V3{1,1,1}*(ridgeStrength*(.22*ribbon+.10*(haze-.5))));
}

V3 shadeLightFlow(State& st,V2 uv){return lightFlowRibbon(st,uv);}
}
