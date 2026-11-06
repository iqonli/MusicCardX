#include "shader_shared.hpp"
// v7 approved implementation, copied without modifying shader formulas.
namespace flow::detail {

V3 fusionHard(State&st,V2 uv){
 // Closer to the upstream DevWinUI/ShaderToy gradient flow: less extra palette fog,
 // emphasizes the rotation field and directional shear.
 V2 p=uv-V2(.5,.5); double aspect=st.width/st.height; p.y/=aspect;
 double angle=(perlin(V2(st.time*.1,p.x*p.y),st.seed^0x5577u)-.5)*TAU+PI; p=rot(p,angle); p.y*=aspect;
 double speed=st.time*2.; p.x+=std::sin(p.y*5.+speed)/30.; p.y+=std::sin(p.x*7.5+speed)/15.;
 double x=smooth(-.3,.2,rot(p,-0.0872665).x), y=smooth(.5,-.3,p.y);
 return sat(bilinear(st.p[0],st.p[1],st.p[2],st.p[3],x,y));}

V3 fusionHardV6(State&st,V2 uv){
 const double structure=st.k[0];
 if(structure<=0.)return fusionHard(st,uv); // exact OLD, including its original stripes
 const double warpStrength=st.k[1];
 const double transitionSoftness=st.k[2];
 const double accentWeight=st.k[3];
 const double cloudMix=st.k[4];
 const double aspect=st.width/st.height;
 V2 coord=uv-V2(.5,.5);
 coord.x*=aspect;
 const double t=st.time*.013;
 // Two decorrelated, low-frequency value-noise fields: no periodic ribbons.
 V2 drift{fbm(coord*1.65+V2(2.1+t,4.4),st.seed^0x43d2u,4),
          fbm(coord*1.65+V2(7.9,-t-3.1),st.seed^0x7b5au,4)};
 V2 q=coord+(drift-V2(.5,.5))*(.85*warpStrength);
 // The fourth extracted palette color can otherwise dominate a large warm stripe.
 // Its weight here is independently tunable; zero substitutes a neutral pair blend.
 V3 neutral=perceptual(st.p[1],st.p[2],.5);
 V3 accent=perceptual(neutral,st.p[3],accentWeight);
 double wide=std::max(.25,transitionSoftness);
 double x=smooth(-.48*wide,.48*wide,q.x+.09*(fbm(q*1.35+V2(1.7,t),st.seed^0x91d7u,3)-.5));
 double y=smooth(-.38*wide,.38*wide,q.y+.08*(fbm(q*1.45+V2(-t,3.6),st.seed^0x6157u,3)-.5));
 V3 gradient=bilinear(st.p[0],st.p[1],st.p[2],accent,x,y);
 // Broad, seed-dependent color fields with smooth, anisotropic Gaussian boundaries.
 // This is a separate color-mixing mechanism, independently controlled by cloudMix.
 double sum=0.;
 V3 lab{};
 const V3 colors[5]={st.p[0],st.p[1],st.p[2],accent,st.p[4]};
 for(int i=0;i<5;i++){
  uint32_t key=st.seed^uint32_t(i+1)*0x9e3779b9u;
  double ax=(rnd(key^0x221u)-.5)*aspect*1.45;
  double ay=(rnd(key^0x733u)-.5)*1.10;
  V2 delta=q-V2(ax,ay);
  double stretch=.78+.55*rnd(key^0x417u);
  double sigma=(.45+.15*double(i%2))*wide;
  double d2=(delta.x*delta.x)/(sigma*sigma*stretch)
          +(delta.y*delta.y)*stretch/(sigma*sigma);
  double w=std::exp(-.70*d2)+.035;
  if(i==3)w*=.35+.65*accentWeight;
  lab+=oklab(colors[i])*w;
  sum+=w;
 }
 V3 cloud=fromOklab(lab/std::max(sum,1e-6));
 V3 clean=perceptual(gradient,cloud,cloudMix);
 if(structure>=1.)return sat(clean);
 return sat(perceptual(fusionHard(st,uv),clean,structure));
}

V3 shadeFusionHard(State& st,V2 uv){return fusionHardV6(st,uv);}
} // namespace flow::detail
