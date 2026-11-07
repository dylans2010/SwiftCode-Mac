#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace airc {

struct MetallibFunction {
    std::string name;
    int type = -1;
    uint8_t hash[32] = {};
    bool hasHash = false;
    uint16_t airMajor = 0, airMinor = 0, langMajor = 0, langMinor = 0;
    uint64_t moduleOffset = 0;
    uint64_t moduleSize = 0;
    std::string hashHex() const;
};

struct Metallib {
    uint16_t versionMajor = 0, versionMinor = 0;
    uint8_t fileType = 0, platform = 0;
    std::vector<MetallibFunction> functions;
    std::string blob;

    std::string module(const MetallibFunction &f) const { return blob.substr(f.moduleOffset, f.moduleSize); }
    const MetallibFunction *find(const std::string &name) const;
};

Metallib parseMetallib(const std::string &data);

std::string sha256Hex(const std::string &bytes);

}
