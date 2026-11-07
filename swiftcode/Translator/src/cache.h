#pragma once

#include "json.h"

#include <cstdint>
#include <map>
#include <string>
#include <vector>

namespace airc {

class Cache {
public:
    explicit Cache(std::string dir) : dir_(std::move(dir)) {}
    bool lookup(const std::string &key, std::vector<uint32_t> &spirv, Json &reflection);
    void store(const std::string &key, const std::vector<uint32_t> &spirv, const Json &reflection);
    void rememberHash(const std::string &hash, const Json &reflection) { byHash_[hash] = reflection; }
    bool reflectionByHash(const std::string &hash, Json &reflection) const;

private:
    struct Entry {
        std::vector<uint32_t> spirv;
        Json reflection;
    };
    std::string dir_;
    std::map<std::string, Entry> mem_;
    std::map<std::string, Json> byHash_;
};

}
