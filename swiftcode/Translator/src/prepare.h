#pragma once

#include <functional>
#include <map>
#include <vector>

namespace llvm {
class BasicBlock;
class Function;
class Module;
}

namespace airc {

struct Construct {
    bool loop = false;
    llvm::BasicBlock *merge = nullptr;
    llvm::BasicBlock *cont = nullptr;
};

struct StructurePlan {
    std::map<llvm::BasicBlock *, Construct> headers;
    std::vector<llvm::BasicBlock *> order;
};

bool prepareFunction(llvm::Module &M, llvm::Function &F, bool gridGuard,
                     const std::function<void(llvm::Function &)> &afterInline = nullptr,
                     std::vector<llvm::Function *> *helpers = nullptr, bool loopGuard = false);

StructurePlan planStructure(llvm::Function &F);

}
