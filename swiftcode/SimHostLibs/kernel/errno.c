#include "yc_kernel.h"

YC_EXPORT int errno = 0;

static int *tsd_errno(void)
{
    yc_uintptr_t *tsd = yc_tsd_base();
    if (tsd == YC_NULL)
        return YC_NULL;
    return (int *)tsd[YC_TSD_ERRNO];
}

YC_EXPORT int *__error(void)
{
    int *p = tsd_errno();
    return p ? p : &errno;
}

static void store_errno(int value)
{
    int *p = tsd_errno();
    if (p)
        *p = value;
    errno = value;
}

YC_EXPORT __int128 cerror_nocancel(int value)
{
    store_errno(value);
    return -1;
}

YC_EXPORT __int128 cerror(int value)
{
    const struct yc_libkernel_functions *fns = yc_libkernel_fns;
    if (fns != YC_NULL && fns->pthread_exit_if_canceled != YC_NULL)
        fns->pthread_exit_if_canceled(value);
    return cerror_nocancel(value);
}

YC_HIDDEN void __swiftcode_set_errno(int value)
{
    store_errno(value);
}

YC_HIDDEN long __swiftcode_stub_enosys(void)
{
    store_errno(YC_ENOSYS);
    return -1;
}
