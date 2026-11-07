#ifndef _TVG_ANIMATION_H_
#define _TVG_ANIMATION_H_

#include "tvgCommon.h"
#include "tvgPicture.h"

struct Animation::Impl
{
    Picture* picture = nullptr;

    Impl()
    {
        picture = Picture::gen();
        picture->ref();
    }

    ~Impl()
    {
        picture->unref();
    }
};

#endif
