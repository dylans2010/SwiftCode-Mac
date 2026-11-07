#pragma once

#include <stdexcept>
#include <string>

namespace airc {

struct Error : std::runtime_error {
    std::string code, detail;
    Error(std::string c, std::string d)
        : std::runtime_error(c + ": " + d), code(std::move(c)), detail(std::move(d)) {}
};

[[noreturn]] inline void fail(const std::string &code, const std::string &detail) { throw Error(code, detail); }

}
