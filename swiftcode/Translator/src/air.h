#pragma once

#include <cstdint>
#include <map>
#include <string>
#include <vector>

namespace llvm {
class Function;
class GlobalVariable;
class MDNode;
class Metadata;
class Module;
}

namespace airc {

struct AirNode {
    int argIndex = -1;
    std::string kind;
    std::string ident;
    std::string fcPredicate;
    std::vector<std::pair<std::string, std::vector<llvm::Metadata *>>> keys;

    bool has(const std::string &k) const;
    int64_t intAt(const std::string &k, unsigned i = 0, int64_t dflt = -1) const;
    std::string strAt(const std::string &k, unsigned i = 0) const;
    int location() const;
    llvm::GlobalVariable *locationGlobal() const;
    int count() const { return (int)intAt("air.location_index", 1, 1); }
    std::string typeName() const { return strAt("air.arg_type_name"); }
    std::string argName() const { return strAt("air.arg_name"); }
    std::string access() const;
};

enum class Stage { Vertex, Fragment, Kernel };
const char *stageName(Stage s);

struct EntryInfo {
    Stage stage;
    llvm::Function *fn = nullptr;
    std::vector<AirNode> outputs;
    std::map<unsigned, AirNode> args;
};

EntryInfo entryInfo(llvm::Module &M, llvm::Function *F);

struct ConstexprSampler {
    llvm::GlobalVariable *global = nullptr;
    uint64_t word0 = 0, word1 = 0;
    std::string source;
    std::string type;
};
std::vector<ConstexprSampler> constexprSamplers(llvm::Module &M);

struct FunctionConstant {
    llvm::GlobalVariable *value = nullptr;
    llvm::GlobalVariable *init = nullptr;
    std::string typeName, name;
    unsigned index = 0;
};
std::vector<FunctionConstant> functionConstants(llvm::Module &M);

struct SamplerFields {
    unsigned addrS, addrT, addrR, magFilter, minFilter, mipFilter, normalized, compare, maxAnisotropy;
    float lodMin, lodMax;
    unsigned borderColor, reduction;
};
SamplerFields decodeSampler(uint64_t word0);

}
