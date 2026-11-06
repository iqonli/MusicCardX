#include "shader_shared.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <exception>
#include <future>
#include <limits>
#include <numeric>
#include <stdexcept>
#include <thread>
#include <vector>
#ifndef FLOW_NO_IMAGE_IO
#include <jpeglib.h>
#include <png.h>
#include <setjmp.h>
#endif


namespace flow {
using namespace detail;
// Each algorithm is in its own compilation unit; this dispatcher does no shading math.
static detail::V3 background(detail::State& st,detail::V2 uv,int,int){
 const auto& e=st.c.effect;
 if(e=="mist")return detail::shadeMist(st,uv);
 if(e=="fusionHard")return detail::shadeFusionHard(st,uv);
 if(e=="fusionSoft")return detail::shadeFusionSoft(st,uv);
 if(e=="lightFlow")return detail::shadeLightFlow(st,uv);
 return {};
}
std::vector<std::string> effects(){return{"mist","fusionHard","fusionSoft","lightFlow"};}
std::array<ParamSpec,3> parameterSpecs(const std::string& effect){
 if(effect=="mist")return {{{"texture_mix",.2,{{0,.10,.20,.30,.40}},"blurred cover influence"},
                           {"warp_strength",.5,{{0,.25,.50,.75,1.}},"multi-scale coordinate distortion"},
                           {"field_size",1.,{{.50,.75,1.,1.25,1.50}},"soft color blob scale"}}};
 if(effect=="fusionHard")return {{{"ridge_strength",.4,{{0,.20,.40,.60,.80}},"curved highlight strength"},
                                 {"warp_strength",.5,{{0,.25,.50,.75,1.}},"multiscale palette warp"},
                                 {"ridge_frequency",5.,{{2.,3.5,5.,6.5,8.}},"number of curved striations"}}};
 if(effect=="fusionSoft")return {{{"fold_strength",.6,{{0,.30,.60,.90,1.20}},"fusionSoft shape folding and swirl"},
                           {"flow_frequency",5.,{{2.,3.5,5.,6.5,8.}},"spatial flow wavelength"},
                           {"lightwave_strength",.5,{{0,.25,.50,.75,1.}},"color breathing strength"}}};
 if(effect=="lightFlow")return {{{"warp_strength",.6,{{0,.30,.60,.90,1.20}},"gradient flow displacement"},
                                  {"ridge_strength",.36,{{0,.18,.36,.54,.72}},"narrow ridge highlight"},
                                  {"ridge_frequency",6.,{{2.,4.,6.,8.,10.}},"curved ridge spatial frequency"}}};
 throw std::runtime_error("Unknown effect for parameter specs: "+effect);
}
std::array<ParamSpec,3> round2Specs(const std::string& effect){
 if(effect=="mist")return {{{"texture_mix",0.,{{0.,.025,.05,.075,.10}},"cover texture, kept near zero"},
                            {"warp_strength",0.,{{0.,.05,.10,.15,.20}},"noise warp, kept near zero"},
                            {"field_size",.50,{{.25,.375,.50,.625,.75}},"extend below previous 0.50 boundary"}}};
 if(effect=="fusionHard")return {{{"rotation_gain",1.,{{.70,.85,1.,1.15,1.30}},"conservative change around legacy rotation"},
                                  {"flow_gain",1.,{{.70,.85,1.,1.15,1.30}},"conservative legacy flow amplitude"},
                                  {"transition_width",1.,{{.70,.85,1.,1.15,1.30}},"original gradient band width"}}};
 if(effect=="fusionSoft")return {{{"fold_strength",.60,{{.30,.45,.60,.75,.90}},"safe fold range"},
                            {"flow_frequency",5.,{{3.,4.,5.,6.,7.}},"safe flow density"},
                            {"lightwave_strength",.25,{{0.,.125,.25,.375,.50}},"exclude rejected >=0.75 lightwaves"}}};
 if(effect=="lightFlow")return {{{"flow_gain",1.,{{.70,.85,1.,1.15,1.30}},"adjust original flow, no aggressive warp"},
                                   {"micro_ridge",0.,{{0.,.015,.03,.045,.06}},"tiny detail only: old at zero"},
                                   {"palette_fog",.11,{{0.,.055,.11,.165,.22}},"original fifth palette color contribution"}}};
 throw std::runtime_error("Unknown effect for round2 specs: "+effect);
}
std::array<ParamSpec,5> round3Specs(const std::string& effect){
 if(effect=="mist")return {{{"texture_mix",.05,{{0.,.025,.05,.075,.10}},"v4 acceptable 0..0.10"},
                           {"warp_strength",.10,{{0.,.05,.10,.15,.20}},"v4 acceptable 0..0.20"},
                           {"field_size",.625,{{.50,.5625,.625,.6875,.75}},"user accepted .50..75"},
                           {"detail_suppression",.50,{{0.,.25,.50,.75,1.}},"lowpass strength of faint artwork texture"},
                           {"palette_softness",1.,{{.55,.775,1.,1.225,1.45}},"width of palette mixture fields"}}};
 if(effect=="fusionHard")return {{{"rotation_gain",1.,{{.85,.925,1.,1.075,1.15}},"conservative OLD rotation neighborhood"},
                                 {"flow_gain",1.,{{.85,.925,1.,1.075,1.15}},"conservative OLD flow neighborhood"},
                                 {"transition_width",1.,{{.85,.925,1.,1.075,1.15}},"gradient width neighborhood"},
                                 {"curve_visibility",.075,{{0.,.0375,.075,.1125,.15}},"very weak curved highlight"},
                                 {"texture_scale",1.,{{.55,.775,1.,1.225,1.45}},"spatial density of fine curved structure"}}};
 if(effect=="fusionSoft")return {{{"old_new_mix",.50,{{0.,.20,.40,.60,.80}},"0 is exact legacy OLD, 1 is v4-style fusionSoft"},
                           {"flow_frequency",5.,{{3.,4.,5.,6.,7.}},"v4 spatial frequency"},
                           {"lightwave_strength",.25,{{0.,.125,.25,.375,.50}},"exclude >=0.75"},
                           {"swirl_strength",0.,{{0.,.25,.50,.75,1.}},"added domain rotation strength"},
                           {"color_binding",0.,{{0.,.2,.4,.6,.8}},"bind mixture back to five cover colors"}}};
 if(effect=="lightFlow")return {{{"flow_gain",1.,{{.85,.925,1.,1.075,1.15}},"near OLD"},
                                   {"micro_ridge",.0075,{{0.,.00375,.0075,.01125,.015}},"user accepted 0..0.015"},
                                   {"palette_fog",.0825,{{0.,.04125,.0825,.12375,.165}},"user accepted 0..0.165"},
                                   {"ridge_width",1.,{{.5,.75,1.,1.25,1.5}},"spatial thickness of the faint ridge"},
                                   {"ridge_contrast",1.,{{.5,.75,1.,1.25,1.5}},"brightness of the faint ridge"}}};
 throw std::runtime_error("Unknown effect for round3 specs: "+effect);
}
std::array<ParamSpec,5> fusionHardV6Specs(){
 return {{{"old_new_mix",1.,{{0.,.25,.50,.75,1.}},"0 is byte-exact OLD; 1 removes both periodic sine shears and v5 ridges"},
          {"nonperiodic_warp",.24,{{0.,.12,.24,.36,.48}},"low-frequency noise displacement; no sine-wave repetition"},
          {"transition_softness",1.,{{.60,.80,1.,1.20,1.40}},"spatial width of smooth color boundaries and Gaussian fields"},
          {"accent_weight",.50,{{0.,.25,.50,.75,1.}},"contribution of fourth palette color (salmon/pink for test1)"},
          {"large_scale_mix",.50,{{0.,.25,.50,.75,1.}},"blend regular smooth color field with broad nonperiodic color clouds"}}};
}
uint32_t seedHash(const std::string& s){uint32_t h=2166136261u; // FNV-1a over UTF-8 bytes: deterministic on both Dart and C++
 for(unsigned char c:s){h=(h^c)*16777619u;}
 h^=h>>13;h*=0x5bd1e995u;h^=h>>15;return h?h:0x9e3779b9u;}
// v7: independently hash seed + effect + parameter name. No platform RNG state,
// thread order or palette contents affect the selected parameter values.
std::array<ParamSpec,5> seedV7Specs(const std::string& effect){
 if(effect=="lightFlow")return {{{"warp_strength",.6,{{0,.30,.60,.90,1.20}},"v4 ribbon displacement"},
 {"ridge_strength",.36,{{0,.18,.36,.54,.72}},"v4 ribbon strength"},
 {"ridge_frequency",6.,{{2.,4.,6.,8.,10.}},"v4 ribbon spatial frequency"},
 {"reserved_1",0.,{{0.,0.,0.,0.,0.}},"unused"},
 {"reserved_2",0.,{{0.,0.,0.,0.,0.}},"unused"}}};

 if(effect=="fusionHard")return fusionHardV6Specs();
 return round3Specs(effect);
}
std::array<double,5> seedV7Parameters(const std::string& effect,const std::string& seed){
 const auto specs=seedV7Specs(effect);
 std::array<double,5> values{};
 for(int i=0;i<5;i++){
  const std::string key="FlowBenchSeedV7|"+seed+"|"+effect+"|"+specs[i].name;
  // FNV-based fixed 32-bit hash, mixed to a 24-bit fractional uniform value.
  uint32_t word=seedHash(key);
  double u=double(hash32(word)>>8)*(1./16777216.);
  const double lo=specs[i].levels.front(),hi=specs[i].levels.back();
  values[i]=lo+(hi-lo)*u;
 }
 return values;
}
Image sampleCover(){Image im;im.width=512;im.height=512;im.rgba.resize(size_t(im.width)*im.height*4);V3 pal[5]={{.99,.30,.38},{.17,.25,.75},{.05,.70,.81},{.95,.73,.21},{.58,.21,.73}};uint32_t seed=seedHash("sample");for(int y=0;y<512;y++)for(int x=0;x<512;x++){V2 p{(x-256)/256.,(y-256)/256.};double a=std::atan2(p.y,p.x),r=length(p);double swirl=a+2.5*r+fbm(p*2+V2(3,1),seed,4)*3;double f=.5+.5*std::sin(swirl*2.2+r*5),q=.5+.5*std::cos(swirl*1.5-r*8);V3 c=bilinear(pal[0],pal[1],pal[2],pal[3],f,q);c=cmix(c,pal[4],.28*smooth(.2,.95,fbm(p*6+V2(5,7),seed,3)));double gleam=.25*std::pow(std::max(0.,std::sin(swirl*3+r*19)),12);c=sat(c+V3{gleam,gleam,gleam});size_t i=(size_t(y)*512+x)*4;im.rgba[i]=uint8_t(clamp(c.x)*255+.5);im.rgba[i+1]=uint8_t(clamp(c.y)*255+.5);im.rgba[i+2]=uint8_t(clamp(c.z)*255+.5);im.rgba[i+3]=255;}return im;}

// Color image ingestion uses the libraries already installed in Termux.
#ifndef FLOW_NO_IMAGE_IO
struct JpegError {jpeg_error_mgr pub;jmp_buf buf;};
void jpegFail(j_common_ptr info){longjmp(((JpegError*)info->err)->buf,1);}
Image loadCover(const std::string& path){FILE*f=std::fopen(path.c_str(),"rb");if(!f)throw std::runtime_error("Cannot open cover: "+path);uint8_t sig[8]={};size_t n=std::fread(sig,1,8,f);std::fclose(f);
 if(n==8&&!png_sig_cmp(sig,0,8)){png_image p{};p.version=PNG_IMAGE_VERSION;if(!png_image_begin_read_from_file(&p,path.c_str()))throw std::runtime_error("PNG decode failed: "+std::string(p.message));p.format=PNG_FORMAT_RGBA;if(p.width==0||p.height==0||uint64_t(p.width)*p.height>16000000){png_image_free(&p);throw std::runtime_error("Cover too large (max 16 million pixels)");}Image im;im.width=int(p.width);im.height=int(p.height);im.rgba.resize(PNG_IMAGE_SIZE(p));if(!png_image_finish_read(&p,nullptr,im.rgba.data(),0,nullptr)){auto msg=std::string(p.message);png_image_free(&p);throw std::runtime_error("PNG decode: "+msg);}png_image_free(&p);return im;}
 if(n>=3&&sig[0]==0xff&&sig[1]==0xd8&&sig[2]==0xff){FILE*in=std::fopen(path.c_str(),"rb");if(!in)throw std::runtime_error("JPEG open error");jpeg_decompress_struct j{};JpegError err{};j.err=jpeg_std_error(&err.pub);err.pub.error_exit=jpegFail;if(setjmp(err.buf)){jpeg_destroy_decompress(&j);std::fclose(in);throw std::runtime_error("JPEG decode error");}jpeg_create_decompress(&j);jpeg_stdio_src(&j,in);jpeg_read_header(&j,TRUE);j.out_color_space=JCS_RGB;jpeg_start_decompress(&j);if(j.output_width==0||j.output_height==0||uint64_t(j.output_width)*j.output_height>16000000){jpeg_destroy_decompress(&j);std::fclose(in);throw std::runtime_error("Cover too large");}Image im;im.width=int(j.output_width);im.height=int(j.output_height);im.rgba.resize(size_t(im.width)*im.height*4);std::vector<uint8_t>row(size_t(im.width)*3);while(j.output_scanline<j.output_height){JSAMPROW ptr=row.data();jpeg_read_scanlines(&j,&ptr,1);size_t dst=size_t(j.output_scanline-1)*im.width*4;for(int x=0;x<im.width;x++){im.rgba[dst+4*x]=row[3*x];im.rgba[dst+4*x+1]=row[3*x+1];im.rgba[dst+4*x+2]=row[3*x+2];im.rgba[dst+4*x+3]=255;}}jpeg_finish_decompress(&j);jpeg_destroy_decompress(&j);std::fclose(in);return im;}
 throw std::runtime_error("Only PNG and JPEG cover images are supported");}
void savePNG(const Image& img,const std::string&path){png_image p{};p.version=PNG_IMAGE_VERSION;p.width=img.width;p.height=img.height;p.format=PNG_FORMAT_RGBA;if(!png_image_write_to_file(&p,path.c_str(),0,img.rgba.data(),0,nullptr))throw std::runtime_error("PNG write error: "+std::string(p.message));}
#endif // FLOW_NO_IMAGE_IO
std::array<Color,5> extractPalette(const Image& image,uint32_t seed){
 if(image.width<=0||image.height<=0)throw std::runtime_error("empty input image");
 struct Sample{V3 rgb,lab;double weight;};std::vector<Sample> points;int stride=std::max(1,int(std::sqrt(double(image.width)*image.height/10000)));for(int y=0;y<image.height;y+=stride)for(int x=0;x<image.width;x+=stride){size_t i=(size_t(y)*image.width+x)*4;if(image.rgba[i+3]<100)continue;V3 c{image.rgba[i]/255.,image.rgba[i+1]/255.,image.rgba[i+2]/255.};V3 lab=oklab(c);double chroma=std::sqrt(lab.y*lab.y+lab.z*lab.z);double weight=.4+std::min(2.5,chroma*8.);points.push_back({c,lab,weight});}if(points.empty())return{{{.5,.5,.5},{.7,.6,.7},{.3,.4,.6},{.7,.7,.5},{.3,.65,.5}}};
 std::array<V3,5> centers{};centers[0]=points[hash32(seed)%points.size()].lab;
 for(int k=1;k<5;k++){std::vector<double> probs(points.size());double sum=0;for(size_t i=0;i<points.size();i++){double dis=1000;for(int j=0;j<k;j++){V3 d=points[i].lab-centers[j];dis=std::min(dis,dot(d,d));}sum+=double(dis)*points[i].weight;probs[i]=sum;}double target=(hash32(seed+uint32_t(k)*22117u)/double(UINT32_MAX))*sum;size_t idx=std::lower_bound(probs.begin(),probs.end(),target)-probs.begin();centers[k]=points[std::min(idx,points.size()-1)].lab;}
 std::array<double,5> pops{};for(int iteration=0;iteration<13;iteration++){std::array<V3,5>sums{};std::array<double,5>weights{};for(const auto&p:points){double best=1e6f;int which=0;for(int k=0;k<5;k++){V3 d=p.lab-centers[k];double dst=dot(d,d);if(dst<best){best=dst;which=k;}}sums[which]+=p.lab*p.weight;weights[which]+=p.weight;}for(int k=0;k<5;k++){if(weights[k]>.0001){centers[k]=sums[k]/double(weights[k]);pops[k]=weights[k];}}}
 std::array<int,5> order{0,1,2,3,4};std::sort(order.begin(),order.end(),[&](int a,int b){return pops[a]>pops[b];});std::array<Color,5> results{};for(int k=0;k<5;k++){V3 lab=centers[order[k]];double chroma=std::sqrt(lab.y*lab.y+lab.z*lab.z);if(chroma<.045){lab.y*=1.30;lab.z*=1.30;}V3 c=fromOklab(lab);results[k]=toColor(c);}return results;}
Image render(Config config,const Image&cover){
 const auto validEffects=effects();
 if(std::find(validEffects.begin(),validEffects.end(),config.effect)==validEffects.end())throw std::runtime_error("Unknown effect: "+config.effect);
 if(config.width<16||config.height<16||config.width>32768||config.height>32768||uint64_t(config.width)*config.height>40000000ull)throw std::runtime_error("Size must be 16..32768, at most 40 million pixels");
 State st;st.width=double(config.width);st.height=double(config.height);st.c=config;st.seed=seedHash(config.seed);st.time=config.phase<0?double(st.seed%30000)/197.:config.phase;
 if(config.engine!=6)throw std::runtime_error("This split-source package supports seed-v7 only");
 const auto specs=seedV7Specs(config.effect);
 const auto seedValues=seedV7Parameters(config.effect,config.seed);
 for(int i=0;i<5;i++){
  st.k[i]=config.params[i]<0.?seedValues[i]:config.params[i];
  if(!std::isfinite(st.k[i])||st.k[i]<specs[i].levels.front()-1e-4||st.k[i]>specs[i].levels.back()+1e-4)
   throw std::runtime_error("Parameter out of screening range: "+specs[i].name);
 }
 const auto pal=config.paletteProvided?config.palette:extractPalette(cover,st.seed);for(int k=0;k<5;k++)st.p[k]=satAdjust(from(pal[k]),1.12);
 st.cover=scaled(texture(cover),512);st.blur1=boxblur(st.cover,7);st.blur2=boxblur(st.cover,20);
 // Heavy shader-style effects are evaluated on a bounded working grid and upscaled.
 int maxw=config.quality==0?400:config.quality==1?660:1080;

 int iw=std::min(maxw,config.width),ih=std::max(1,int(std::round(double(config.height)*iw/config.width)));
 if(ih>maxw){ih=maxw;iw=std::max(1,int(std::round(double(config.width)*ih/config.height)));}
 std::vector<V3> work(size_t(iw)*ih);
 int nt=config.threads>0?config.threads:int(std::thread::hardware_concurrency());nt=std::clamp(nt,1,8);nt=std::min(nt,ih);
 auto job=[&](int lo,int hi){for(int y=lo;y<hi;y++)for(int x=0;x<iw;x++){V2 uv{(x+.5)/iw,(y+.5)/ih};V3 col=background(st,uv,x,y);work[size_t(y)*iw+x]=sat(col);}};
 std::vector<std::thread>workers;for(int i=1;i<nt;i++)workers.emplace_back(job,i*ih/nt,(i+1)*ih/nt);job(0,ih/nt);for(auto& w:workers)w.join();
 Image out;out.width=config.width;out.height=config.height;out.rgba.resize(size_t(out.width)*out.height*4);auto sample=[&](int x,int y){return work[size_t(std::clamp(y,0,ih-1))*iw+std::clamp(x,0,iw-1)];};
 // Cubic reconstruction with soft anti-banding dither. Uses global pixel coords, never thread ordering.
 auto cubic=[](double x){x=std::abs(x);if(x<1)return (1.5*x-2.5)*x*x+1;if(x<2)return ((-.5*x+2.5)*x-4.)*x+2;return 0.;};
 auto upscale=[&](int lo,int hi){for(int y=lo;y<hi;y++){double sy=(y+.5)*ih/out.height-.5;int yi=int(std::floor(sy));for(int x=0;x<out.width;x++){double sx=(x+.5)*iw/out.width-.5;int xi=int(std::floor(sx));V3 c{};double weights=0;for(int j=-1;j<=2;j++)for(int i=-1;i<=2;i++){double w=cubic(sx-(xi+i))*cubic(sy-(yi+j));c+=sample(xi+i,yi+j)*w;weights+=w;}c=c/std::max(.0001,weights);double d=(rnd(uint32_t(x)*374761393u^uint32_t(y)*668265263u^st.seed)-.5)/255.;c=sat(c+V3{d,d,d});size_t off=(size_t(y)*out.width+x)*4;out.rgba[off]=uint8_t(clamp(c.x)*255+.5);out.rgba[off+1]=uint8_t(clamp(c.y)*255+.5);out.rgba[off+2]=uint8_t(clamp(c.z)*255+.5);out.rgba[off+3]=255;}}};
 workers.clear();nt=std::min(nt,out.height);for(int i=1;i<nt;i++)workers.emplace_back(upscale,i*out.height/nt,(i+1)*out.height/nt);upscale(0,out.height/nt);for(auto&w:workers)w.join();return out;
}
} // namespace flow
