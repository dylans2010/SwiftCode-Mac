#ifndef _TVG_ACCESSOR_H_
#define _TVG_ACCESSOR_H_

#include "tvgPaint.h"

namespace tvg
{

struct AccessorEntity
{
    uint32_t id;
    Paint* paint;
    char* name;
};

struct AccessorCallback
{
    function<bool(const Paint* paint, void* data)> func;
    void* data;
};

struct AccessorIterator
{
    virtual ~AccessorIterator() {}
    virtual const Paint* next() = 0;

    static AccessorIterator* iterator(const Paint* paint)
    {
        return PAINT(paint)->iterator();
    }
};

}

#endif
