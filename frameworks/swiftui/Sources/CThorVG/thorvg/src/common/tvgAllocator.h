#ifndef _TVG_ALLOCATOR_H_
#define _TVG_ALLOCATOR_H_

#include <cstdlib>
#include <cstddef>

namespace tvg
{
    template<typename T = void>
    static inline T* malloc(size_t size)
    {
        return static_cast<T*>(std::malloc(size));
    }

    template<typename T = void>
    static inline T* calloc(size_t nmem, size_t size)
    {
        return static_cast<T*>(std::calloc(nmem, size));
    }

    template<typename T = void>
    static inline T* realloc(T* ptr, size_t size)
    {
        return static_cast<T*>(std::realloc(ptr, size));
    }

    template<typename T = void>
    static inline void free(T* ptr)
    {
        std::free(ptr);
    }
}

#endif
