#ifndef _TVG_PNG_LOADER_H_
#define _TVG_PNG_LOADER_H_

#include "tvgLodePng.h"
#include "tvgTaskScheduler.h"

struct PngLoader : BitmapLoader, Task
{
    PngLoader();
    ~PngLoader();

    Result open(const char* path, const LoaderOps& ops) override;
    Result open(const char* data, uint32_t size, const LoaderOps& ops) override;
    bool read() override;

    RenderSurface* bitmap() override;

private:
    LodePNGState state;
    unsigned char* data = nullptr;
    uint32_t size = 0;

    void run(unsigned tid) override;
};

#endif
