#pragma once
#include <array>
#include <cstdint>
#include <string>
#include <limits>
#include <vector>

namespace flow {
struct Color { double r=0, g=0, b=0; };
struct Image {
    int width=0, height=0;
    std::vector<uint8_t> rgba;
};
struct Config {
    std::string effect="fusionSoft";
    int width=1280, height=720;
    std::string seed="114514";
    double phase=-1.0; // negative: reproducible seed-derived phase
    int quality=1; // 0=fast, 1=balanced, 2=high
    int threads=0; // 0=auto, max 8
    bool light=false;
    int engine=6; // 1=legacy, 2=v2, 3=v4, 4=v5, 5=fusionHard v6, 6=seed-v7 (default)
    std::array<double,5> params{{-1.,-1.,-1.,-1.,-1.}}; // -1 uses mode-specific default
    std::array<Color,5> palette{};
    bool paletteProvided=false;
};
struct ParamSpec {
    std::string name;
    double defaultValue;
    std::array<double,5> levels;
    std::string note;
};
std::array<ParamSpec,3> parameterSpecs(const std::string& effect);
std::array<ParamSpec,3> round2Specs(const std::string& effect);
std::array<ParamSpec,5> round3Specs(const std::string& effect);
std::array<ParamSpec,5> fusionHardV6Specs();
std::array<ParamSpec,5> seedV7Specs(const std::string& effect);
std::array<double,5> seedV7Parameters(const std::string& effect, const std::string& seed);
std::vector<std::string> effects();
uint32_t seedHash(const std::string& seed);
Image sampleCover();
Image loadCover(const std::string& path);
void savePNG(const Image& img,const std::string& path);
std::array<Color,5> extractPalette(const Image& image, uint32_t seed);
Image render(Config config, const Image& cover);
}
