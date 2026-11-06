#include "shader_shared.hpp"
// v7 approved implementation, copied without modifying shader formulas.
namespace flow::detail {

V3 mistV5(State&st,V2 uv){
 const double textureMix=st.k[0], warpStrength=st.k[1], fieldSize=st.k[2];
 const double detailSuppression=st.k[3], paletteSoftness=st.k[4];
 const double aspect=st.width/st.height;
 V2 xy=uv-V2(.5,.5);xy.x*=aspect;
 V2 coarse{fbm(xy*1.9+V2(st.time*.011,8.3),st.seed^0x51u,4),
           fbm(xy*1.9+V2(2.7,-st.time*.012),st.seed^0x9au,4)};
 V2 fine{fbm(xy*3.6+V2(1.6,st.time*.01),st.seed^0x19u,3),
         fbm(xy*3.6+V2(7.4,1.2),st.seed^0x31u,3)};
 V2 displaced=xy+(coarse-V2(.5,.5))*(.54*warpStrength)
                +(fine-V2(.5,.5))*(.13*warpStrength);
 double weight[5],total=0;
 for(int i=0;i<5;i++){
  double angle=TAU*(double(i)+.18*rnd(st.seed^uint32_t(i*811u)))/5.+st.time*.008*(i%2?1.:-1.);
  double radius=(i==4?.10:.43)*std::max(.1,fieldSize);
  V2 anchor{radius*std::cos(angle)*(i==4?1.:aspect*.65),radius*std::sin(angle)};
  V2 d=displaced-anchor;
  double sigma=(i==4?.48:.42)*std::max(.35,fieldSize)*paletteSoftness;
  weight[i]=std::exp(-.85*dot(d,d)/(sigma*sigma))+.035;
  total+=weight[i];
 }
 V3 lab{};for(int i=0;i<5;i++)lab+=oklab(st.p[i])*(weight[i]/total);
 V3 field=fromOklab(lab);
 V2 q=rot(displaced,st.time*.018+.3);q.x/=aspect;q=q*.49+V2(.5,.5);
 // 0=blurred artwork with relatively more texture; 1=strongly defocused artwork.
 // Texture mix has a small nonzero anchor in the screen so this control is observable.
 V3 image=cmix(tex(st.blur1,q),tex(st.blur2,q),detailSuppression);
 V3 c=perceptual(field,image,textureMix);
 double sheen=fbm(displaced*1.7+V2(3.2,5.1),st.seed^0x777u,3);
 c+=V3{1,1,1}*((sheen-.5)*(.065-.023*detailSuppression));
 return sat(satAdjust(c,1.09));
}

V3 shadeMist(State& st,V2 uv){return mistV5(st,uv);}
} // namespace flow::detail
