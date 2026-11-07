#include "yc_platform.h"

#define OS_SYNC_SHARED 1u
#define OS_CLOCK_MACH_ABSOLUTE_TIME 32u

static int fail(int err)
{
    __swiftcode_set_errno(err);
    return -1;
}

static int pick_op(void *addr, yc_size_t size, yc_u32 flags, yc_u32 *op)
{
    if (addr == YC_NULL || (flags & ~OS_SYNC_SHARED) != 0)
        return YC_EINVAL;
    if (size == 4)
        *op = (flags & OS_SYNC_SHARED) ? YC_UL_COMPARE_AND_WAIT_SHARED : YC_UL_COMPARE_AND_WAIT;
    else if (size == 8)
        *op = (flags & OS_SYNC_SHARED) ? YC_UL_COMPARE_AND_WAIT64_SHARED : YC_UL_COMPARE_AND_WAIT64;
    else
        return YC_EINVAL;
    if ((yc_uintptr_t)addr & (size - 1))
        return YC_EINVAL;
    return 0;
}

static int do_wait(void *addr, yc_u64 value, yc_size_t size, yc_u32 flags, yc_u64 timeout_ns)
{
    yc_u32 op;
    int err = pick_op(addr, size, flags, &op);
    if (err)
        return fail(err);
    if (size == 4 && (value >> 32) != 0)
        return fail(YC_EINVAL);
    int r = YC_KFN(__ulock_wait2)(op | YC_ULF_NO_ERRNO, addr, value, timeout_ns, 0);
    if (r < 0)
        return fail(-r);
    return r;
}

YC_EXPORT int YC_FN(os_sync_wait_on_address)(void *addr, yc_u64 value, yc_size_t size, yc_u32 flags)
{
    return do_wait(addr, value, size, flags, 0);
}

YC_EXPORT int YC_FN(os_sync_wait_on_address_with_timeout)(void *addr, yc_u64 value, yc_size_t size, yc_u32 flags,
                                                          yc_u32 clockid, yc_u64 timeout_ns)
{
    if (clockid != OS_CLOCK_MACH_ABSOLUTE_TIME || timeout_ns == 0)
        return fail(YC_EINVAL);
    return do_wait(addr, value, size, flags, timeout_ns);
}

static yc_u64 ticks_to_ns(yc_u64 ticks, struct yc_mach_timebase_info tb)
{
    if (tb.numer == tb.denom || tb.denom == 0)
        return ticks;
    yc_u64 q = ticks / tb.denom, r = ticks % tb.denom;
    return q * tb.numer + (r * tb.numer) / tb.denom;
}

YC_EXPORT int YC_FN(os_sync_wait_on_address_with_deadline)(void *addr, yc_u64 value, yc_size_t size, yc_u32 flags,
                                                           yc_u32 clockid, yc_u64 deadline)
{
    if (clockid != OS_CLOCK_MACH_ABSOLUTE_TIME)
        return fail(YC_EINVAL);
    yc_u32 op;
    int err = pick_op(addr, size, flags, &op);
    if (err)
        return fail(err);
    yc_u64 now = YC_KFN(mach_absolute_time)();
    if (deadline <= now)
        return fail(YC_ETIMEDOUT);
    struct yc_mach_timebase_info tb = { 1, 1 };
    if (YC_KFN(mach_timebase_info)(&tb) != 0)
        tb.numer = tb.denom = 1;
    yc_u64 ns = ticks_to_ns(deadline - now, tb);
    return do_wait(addr, value, size, flags, ns ? ns : 1);
}

static int do_wake(void *addr, yc_size_t size, yc_u32 flags, yc_u32 extra)
{
    yc_u32 op;
    int err = pick_op(addr, size, flags, &op);
    if (err)
        return fail(err);
    int r = YC_KFN(__ulock_wake)(op | extra | YC_ULF_NO_ERRNO, addr, 0);
    if (r < 0)
        return fail(-r);
    return 0;
}

YC_EXPORT int YC_FN(os_sync_wake_by_address_any)(void *addr, yc_size_t size, yc_u32 flags)
{
    return do_wake(addr, size, flags, 0);
}

YC_EXPORT int YC_FN(os_sync_wake_by_address_all)(void *addr, yc_size_t size, yc_u32 flags)
{
    return do_wake(addr, size, flags, YC_ULF_WAKE_ALL);
}
