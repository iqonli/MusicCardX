#include "shader_shared.hpp"
// V2 flow field, experimental haze-only rendering: explicit ribbon highlight disabled.
namespace flow::detail {
V3 lightFlowRibbon(State&st,V2 uv){
 const double warpStrength=st.k[0],hazeStrength=st.k[1],hazeScale=st.k[2];
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
 double haze=fbm(p*hazeScale+V2(st.time*.018,3),st.seed^0x383u,4);
 V3 mixed=perceptual(base,st.p[4],.12+.22*smooth(.38,.75,haze));
 return sat(mixed+V3{1,1,1}*(hazeStrength*.10*(haze-.5)));
}

V3 shadeLightFlow(State& st,V2 uv){return lightFlowRibbon(st,uv);}
}
