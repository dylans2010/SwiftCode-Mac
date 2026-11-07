#ifndef _TVG_RAW_LOADER_H_
#define _TVG_RAW_LOADER_H_

struct RawLoader : BitmapLoader
{
    RawLoader() : BitmapLoader(FileType::Raw) {}
    ~RawLoader();

    using Loader::open;
    bool open(const uint32_t* data, uint32_t w, uint32_t h, ColorSpace cs, Ownership owner);
    bool read() override;
};

#endif
