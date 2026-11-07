#ifndef _TVG_COLOR_H_
#define _TVG_COLOR_H_

#include "tvgCommon.h"

namespace tvg
{
    struct RGB
    {
        uint8_t r, g, b;
    };

    struct RGBA
    {
        uint8_t r, g, b, a;
    };

    struct HSL
    {
        float h, s, l;
    };
}

#endif
