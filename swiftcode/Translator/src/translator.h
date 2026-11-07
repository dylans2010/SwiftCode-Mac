#pragma once

#include "json.h"

#include <cstdint>
#include <functional>
#include <map>
#include <string>
#include <vector>

namespace airc {

struct TranslateOptions {
    std::map<std::string, unsigned> varyings;
    bool haveVaryings = false;
    std::string linkedVertexHash;
    bool optimize = false;
    std::vector<std::string> linkModules;
    bool wrapVisible = false;
    std::function<bool(const std::string &name, std::string &module)> resolveVisible;
    bool wantAssembly = false;
    uint32_t loopLimit = 0;

    std::map<unsigned, double> functionConstantValues;
};

struct TranslateResult {
    std::vector<uint32_t> spirv;
    Json reflection;
    std::string assembly;
};

TranslateResult translate(const std::string &module, const std::string &name, const std::string &hashHex, int kind,
                          const TranslateOptions &opts);

extern const char *kTranslatorVersion;

}
