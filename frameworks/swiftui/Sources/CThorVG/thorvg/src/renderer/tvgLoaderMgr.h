#ifndef _TVG_LOADER_MGR_H_
#define _TVG_LOADER_MGR_H_

#include "tvgLoader.h"

namespace tvg
{

struct LoaderMgr
{
    static bool init();
    static bool term();
    static Loader* loader(const char* filename, LoaderOps& ops, Result& ret);
    static Loader* loader(const char* data, uint32_t size, const char* mimeType, LoaderOps& ops, Result& ret);
    static Loader* loader(const uint32_t* data, uint32_t w, uint32_t h, ColorSpace cs, Ownership owner);
    static Loader* loader(const char* name, const char* data, uint32_t size, const char* mimeType, const LoaderOps& ops);
    static Loader* font(const char* name);
    static Loader* anyfont();
    static bool retrieve(const char* filename);
    static bool retrieve(Loader* loader);
};

}

#endif
