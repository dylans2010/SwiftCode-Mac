#ifndef _TVG_JPG_LOADER_H_
#define _TVG_JPG_LOADER_H_

#include "tvgLoader.h"
#include "tvgTaskScheduler.h"
#include "tvgJpgd.h"

struct JpgLoader : BitmapLoader, Task
{
    JpgLoader() : BitmapLoader(FileType::Jpg) {}
    ~JpgLoader();

    Result open(const char* path, const LoaderOps& ops) override;
    Result open(const char* data, uint32_t size, const LoaderOps& ops) override;
    bool read() override;
    bool close() override;

    RenderSurface* bitmap() override;

private:
    jpeg_decoder* decoder = nullptr;
    char* data = nullptr;

    void clear();
    void run(unsigned tid) override;
};

#endif
