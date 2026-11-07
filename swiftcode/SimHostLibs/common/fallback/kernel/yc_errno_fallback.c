#include "yc_base.h"

extern int errno;

static int **tsd_errno_slot(void)
{
    yc_uintptr_t tsd;
    __asm__ volatile("mrs %0, tpidrro_el0" : "=r"(tsd));
    return tsd ? (int **)(tsd + 8) : YC_NULL;
}

YC_EXPORT int *__error(void)
{
    int **slot = tsd_errno_slot();
    if (slot && *slot)
        return *slot;
    return &errno;
}

static __int128 store_errno(int value)
{
    int **slot = tsd_errno_slot();
    if (slot && *slot)
        **slot = value;
    errno = value;
    return -1;
}

YC_EXPORT __int128 cerror(int value)
{
    return store_errno(value);
}

YC_EXPORT __int128 cerror_nocancel(int value)
{
    return store_errno(value);
}
