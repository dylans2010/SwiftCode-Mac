#include "tvgJpgLoader.h"

void JpgLoader::clear()
{
    jpgdDelete(decoder);
    if (owner != Ownership::Borrow) tvg::free(data);
    decoder = nullptr;
    data = nullptr;
    owner = Ownership::Borrow;
}

void JpgLoader::run(unsigned tid)
{
    surface.setup((pixel_t*)jpgdDecompress(decoder), static_cast<uint32_t>(w), static_cast<uint32_t>(w), static_cast<uint32_t>(h), sizeof(uint32_t), ColorSpace::XBGR8888);
    clear();
}

JpgLoader::~JpgLoader()
{
    done();
    clear();
    tvg::free(surface.buf8);
}

Result JpgLoader::open(const char* path, const LoaderOps& ops)
{
#ifdef THORVG_FILE_IO_SUPPORT
    int width, height;
    if (!(decoder = jpgdHeader(path, &width, &height))) return Result::InvalidArguments;

    w = static_cast<float>(width);
    h = static_cast<float>(height);
    owner = Ownership::Transfer;

    return Result::Success;
#else
    return Result::NonSupport;
#endif
}

Result JpgLoader::open(const char* data, uint32_t size, const LoaderOps& ops)
{
    if (ops.owner == Ownership::Copy) {
        this->data = tvg::malloc<char>(size);
        memcpy((char *)this->data, data, size);
    } else {
        this->data = (char *) data;
    }
    owner = ops.owner;

    int width, height;
    decoder = jpgdHeader(this->data, size, &width, &height);
    if (!decoder) return Result::InvalidArguments;

    w = static_cast<float>(width);
    h = static_cast<float>(height);

    return Result::Success;
}

bool JpgLoader::read()
{
    if (!Loader::read()) return true;

    if (!decoder || w == 0 || h == 0) return false;

    TaskScheduler::request(this);

    return true;
}

bool JpgLoader::close()
{
    if (!Loader::close()) return false;
    this->done();
    return true;
}

RenderSurface* JpgLoader::bitmap()
{
    this->done();
    return BitmapLoader::bitmap();
}
