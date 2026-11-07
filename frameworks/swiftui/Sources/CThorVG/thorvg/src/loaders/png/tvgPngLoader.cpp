#include <memory.h>
#include "tvgLoader.h"
#include "tvgPngLoader.h"

void PngLoader::run(unsigned tid)
{
    auto width = static_cast<unsigned>(w);
    auto height = static_cast<unsigned>(h);

    state.info_raw.colortype = LCT_RGBA;

    if (lodepng_decode(&surface.buf8, &width, &height, &state, data, size)) TVGERR("PNG", "Failed to decode image");
    else if (state.info_png.iccp_defined && lodepng_toSrgb(surface.buf8, surface.buf8, width, height, &state)) TVGERR("PNG", "Unsupported ICC color profile");

    surface.setup(surface.buf32, width, width, height, sizeof(uint32_t), ColorSpace::ABGR8888S);
}

PngLoader::PngLoader() : BitmapLoader(FileType::Png)
{
    lodepng_state_init(&state);
}

PngLoader::~PngLoader()
{
    done();
    if (owner != Ownership::Borrow) tvg::free(data);
    tvg::free(surface.buf8);
    lodepng_state_cleanup(&state);
}

Result PngLoader::open(const char* path, const LoaderOps& ops)
{
#ifdef THORVG_FILE_IO_SUPPORT
    if (!(data = (unsigned char*)Loader::open(path, size))) return Result::InvalidArguments;
    owner = Ownership::Transfer;

    lodepng_state_init(&state);

    unsigned int width, height;
    if (lodepng_inspect(&width, &height, &state, data, size) > 0) return Result::InvalidArguments;
    w = static_cast<float>(width);
    h = static_cast<float>(height);
    return Result::Success;
#else
    return Result::NonSupport;
#endif
}

Result PngLoader::open(const char* data, uint32_t size, const LoaderOps& ops)
{
    unsigned int width, height;
    if (lodepng_inspect(&width, &height, &state, (unsigned char*)(data), size) > 0) return Result::InvalidArguments;

    if (ops.owner == Ownership::Copy) {
        this->data = tvg::malloc<unsigned char>(size);
        memcpy((unsigned char *)this->data, data, size);
    } else {
        this->data = (unsigned char *) data;
    }
    owner = ops.owner;
    w = static_cast<float>(width);
    h = static_cast<float>(height);
    this->size = size;

    return Result::Success;
}

bool PngLoader::read()
{
    if (!data || w == 0 || h == 0) return false;

    if (!Loader::read()) return true;

    TaskScheduler::request(this);

    return true;
}

RenderSurface* PngLoader::bitmap()
{
    this->done();
    return BitmapLoader::bitmap();
}
