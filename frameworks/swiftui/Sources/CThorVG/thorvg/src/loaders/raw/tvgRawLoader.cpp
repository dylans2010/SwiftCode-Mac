#include "tvgLoader.h"
#include "tvgRawLoader.h"

RawLoader::~RawLoader()
{
    if (owner != Ownership::Borrow) tvg::free(surface.buf32);
}

bool RawLoader::open(const uint32_t* data, uint32_t w, uint32_t h, ColorSpace cs, Ownership owner)
{
    if (!Loader::read()) return true;

    if (!data || w == 0 || h == 0) return false;

    this->w = (float)w;
    this->h = (float)h;
    this->owner = owner;

    if (owner == Ownership::Copy) {
        surface.buf32 = tvg::malloc<uint32_t>(sizeof(uint32_t) * w * h);
        memcpy((void*)surface.buf32, data, sizeof(uint32_t) * w * h);
    } else {
        surface.buf32 = const_cast<uint32_t*>(data);
    }

    surface.setup(surface.buf32, w, w, h, sizeof(uint32_t), cs);
    return true;
}

bool RawLoader::read()
{
    Loader::read();

    return true;
}
