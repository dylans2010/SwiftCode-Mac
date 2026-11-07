#ifndef _TVG_SAVE_MODULE_H_
#define _TVG_SAVE_MODULE_H_

#include "tvgCommon.h"

namespace tvg
{

struct SaveModule
{
    virtual ~SaveModule() {}
    virtual bool save(Paint* paint, Paint* bg, const char* filename, uint32_t quality) = 0;
    virtual bool save(Animation* animation, Paint* bg, const char* filename, uint32_t quality, uint32_t fps) = 0;
    virtual bool close() = 0;
};

}

#endif
