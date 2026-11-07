#ifndef _TVG_LOCK_H_
#define _TVG_LOCK_H_

#include <mutex>
#include "tvgTaskScheduler.h"

namespace tvg
{
#ifdef THORVG_THREAD_SUPPORT
    struct Key
    {
        std::mutex mtx;

        void lock()
        {
            mtx.lock();
        }

        void unlock()
        {
            mtx.unlock();
        }
    };

    struct StrictKey : Key
    {
    };

    struct ScopedLock
    {
        Key* key = nullptr;

        ScopedLock(Key& k)
        {
            if (TaskScheduler::threads() > 0) {
                k.mtx.lock();
                key = &k;
            }
        }

        ScopedLock(StrictKey& k)
        {
            k.mtx.lock();
            key = &k;
        }

        ~ScopedLock()
        {
            if (key) key->mtx.unlock();
        }
    };
#else
    struct Key {};

    struct StrictKey : Key
    {
#ifdef __STDCPP_THREADS__
        std::mutex mtx;
#endif

        void lock()
        {
#ifdef __STDCPP_THREADS__
            mtx.lock();
#endif
        }

        void unlock()
        {
#ifdef __STDCPP_THREADS__
            mtx.unlock();
#endif
        }
    };

    struct ScopedLock
    {
        StrictKey* key = nullptr;

        ScopedLock(Key& k) {}

        ScopedLock(StrictKey& k)
        {
            k.lock();
            key = &k;
        }

        ~ScopedLock()
        {
            if (key) key->unlock();
        }
    };
#endif
}

#endif
