#include "config.h"
#include "tvgCommon.h"
#include "tvgCompressor.h"

namespace tvg {

size_t b64Decode(const char* encoded, const size_t len, char** decoded)
{
    static constexpr const char B64_INDEX[256] =
    {
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  62, 63, 62, 62, 63, 52, 53, 54, 55, 56, 57,
        58, 59, 60, 61, 0,  0,  0,  0,  0,  0,  0,  0,  1,  2,  3,  4,  5,  6,
        7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
        25, 0,  0,  0,  0,  63, 0,  26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36,
        37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51
    };

    if (!decoded || !encoded || len == 0) return 0;

    auto reserved = 3 * (1 + (len >> 2)) + 1;
    auto output = tvg::malloc<char>(reserved * sizeof(char));
    if (!output) return 0;
    output[reserved - 1] = '\0';

    size_t idx = 0;

    while (*encoded && *(encoded + 1)) {
        if (*encoded <= 0x20) {
            ++encoded;
            continue;
        }

        auto value1 = B64_INDEX[(size_t)encoded[0]];
        auto value2 = B64_INDEX[(size_t)encoded[1]];
        output[idx++] = (value1 << 2) + ((value2 & 0x30) >> 4);

        if (!encoded[2] || encoded[3] < 0 || encoded[2] == '=' || encoded[2] == '.') break;
        auto value3 = B64_INDEX[(size_t)encoded[2]];
        output[idx++] = ((value2 & 0x0f) << 4) + ((value3 & 0x3c) >> 2);

        if (!encoded[3] || encoded[3] < 0 || encoded[3] == '=' || encoded[3] == '.') break;
        auto value4 = B64_INDEX[(size_t)encoded[3]];
        output[idx++] = ((value3 & 0x03) << 6) + value4;
        encoded += 4;
    }
    *decoded = output;
    return idx;
}

unsigned long djb2Encode(const char* str)
{
    if (!str) return 0;

    unsigned long hash = 5381;
    int c;

    while ((c = *str++)) {
        hash = ((hash << 5) + hash) + c;
    }
    return hash;
}

}
