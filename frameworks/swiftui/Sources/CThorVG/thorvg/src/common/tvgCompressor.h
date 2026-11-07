#ifndef _TVG_COMPRESSOR_H_
#define _TVG_COMPRESSOR_H_

#include <cstdint>

namespace tvg
{
    size_t b64Decode(const char* encoded, const size_t len, char** decoded);
    unsigned long djb2Encode(const char* str);
}

#endif
