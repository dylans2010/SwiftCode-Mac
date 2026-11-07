#include "yc_kernel.h"

static inline yc_u64 yc_read_cntvct(void)
{
    yc_u64 v;
    __asm__ volatile("isb\n\tmrs %0, cntvct_el0" : "=r"(v) : : "memory");
    return v;
}

static inline int yc_direct_clock(void)
{
    return (yc_commpage_u8(YC_COMM_FAST_FLAGS) & YC_FAST_DIRECT_CLOCK) != 0;
}

static inline yc_u64 yc_scale_counter(yc_u64 counter)
{
    yc_u64 m = yc_commpage_u64(YC_COMM_CLOCK_MULTIPLIER);
    if (m == 0)
        return counter;
    yc_u64 shift = yc_commpage_u64(YC_COMM_CLOCK_SHIFT);
    unsigned __int128 p = (unsigned __int128)counter * m;
    return (yc_u64)(p >> (shift & 127));
}

static yc_u64 yc_direct_absolute(void)
{
    for (;;) {
        yc_u64 before = yc_commpage_u64(YC_COMM_TIMEBASE_OFFSET);
        yc_u64 counter = yc_read_cntvct();
        yc_u64 after = yc_commpage_u64(YC_COMM_TIMEBASE_OFFSET);
        if (before == after)
            return yc_scale_counter(counter) + before;
    }
}

YC_EXPORT yc_u64 mach_absolute_time(void)
{
    if (yc_direct_clock())
        return yc_direct_absolute();
    return YC_MACH0(YC_TRAP_ABSOLUTE_TIME);
}

YC_EXPORT yc_u64 mach_continuous_time(void)
{
    if (yc_direct_clock()) {
        for (;;) {
            yc_u64 before = yc_commpage_u64(YC_COMM_CONT_TIMEBASE);
            yc_u64 absolute = yc_direct_absolute();
            if (yc_commpage_u64(YC_COMM_CONT_TIMEBASE) == before)
                return absolute + before;
        }
    }
    return YC_MACH0(YC_TRAP_CONTINUOUS_TIME);
}

YC_EXPORT yc_u64 mach_approximate_time(void)
{
    return mach_absolute_time();
}

YC_EXPORT yc_u64 mach_continuous_approximate_time(void)
{
    return mach_continuous_time();
}

static struct yc_mach_timebase_info yc_timebase_cache;

YC_EXPORT int mach_timebase_info(struct yc_mach_timebase_info *info)
{
    if (yc_timebase_cache.denom == 0) {
        struct yc_mach_timebase_info tb = {0, 0};
        int kr = (int)YC_MACH1(YC_TRAP_TIMEBASE_INFO, &tb);
        if (kr != YC_KERN_SUCCESS)
            return kr;
        if (tb.denom == 0)
            return YC_KERN_FAILURE;
        yc_timebase_cache = tb;
    }
    if (info == YC_NULL)
        return YC_KERN_INVALID_ARGUMENT;
    *info = yc_timebase_cache;
    return YC_KERN_SUCCESS;
}

YC_EXPORT yc_u64 mach_boottime_usec(void)
{
    return yc_commpage_u64(YC_COMM_BOOTTIME_USEC);
}

struct yc_timeval {
    yc_i64 tv_sec;
    yc_i32 tv_usec;
};
struct yc_timespec {
    yc_i64 tv_sec;
    yc_i64 tv_nsec;
};
int __gettimeofday(struct yc_timeval *tp, void *tzp, yc_u64 *mach_time);

YC_EXPORT int __commpage_gettimeofday(struct yc_timeval *tp)
{
    if (!yc_direct_clock())
        return 1;
    const volatile yc_u64 *d = (const volatile yc_u64 *)(yc_uintptr_t)(YC_COMMPAGE_RW + YC_COMM_NEWTIMEOFDAY);
    yc_u64 tick, sec, frac, scale, per_sec;
    for (;;) {
        tick = d[0];
        if (tick == 0)
            return 1;
        __asm__ volatile("dmb ishld" ::: "memory");
        sec = d[1];
        frac = d[2];
        scale = d[3];
        per_sec = d[4];
        __asm__ volatile("dmb ishld" ::: "memory");
        if (d[0] == tick)
            break;
    }
    yc_u64 now = yc_direct_absolute();
    yc_u64 delta = now >= tick ? now - tick : 0;
    if (per_sec == 0 || delta >= per_sec)
        return 1;
    yc_u64 frac2 = frac + delta * scale;
    if (frac2 < frac)
        sec += 1;
    if (tp != YC_NULL) {
        tp->tv_sec = (yc_i64)sec;
        tp->tv_usec = (yc_i32)(((unsigned __int128)frac2 * 1000000u) >> 64);
    }
    return 0;
}

YC_EXPORT int mach_get_times(yc_u64 *absolute_time, yc_u64 *continuous_time, struct yc_timespec *tp)
{
    if (tp != YC_NULL) {
        struct yc_timeval tv = {0, 0};
        if (__commpage_gettimeofday(&tv) != 0 && __gettimeofday(&tv, YC_NULL, YC_NULL) != 0)
            return YC_KERN_FAILURE;
        tp->tv_sec = tv.tv_sec;
        tp->tv_nsec = (yc_i64)tv.tv_usec * 1000;
    }
    if (absolute_time != YC_NULL)
        *absolute_time = mach_absolute_time();
    if (continuous_time != YC_NULL)
        *continuous_time = mach_continuous_time();
    return YC_KERN_SUCCESS;
}

YC_EXPORT yc_port_t mach_task_self(void)
{
    return mach_task_self_;
}

YC_EXPORT yc_port_t mach_host_self(void)
{
    return (yc_port_t)YC_MACH0(YC_TRAP_HOST_SELF);
}

YC_EXPORT yc_port_t mach_thread_self(void)
{
    return (yc_port_t)YC_MACH0(YC_TRAP_THREAD_SELF);
}

YC_EXPORT int mach_task_is_self(yc_port_t task)
{
    return task == mach_task_self_;
}

YC_EXPORT int mach_port_allocate(yc_port_t task, yc_u32 right, yc_port_t *name)
{
    return (int)YC_MACH3(YC_TRAP_PORT_ALLOCATE, task, right, name);
}

YC_EXPORT int mach_port_deallocate(yc_port_t task, yc_port_t name)
{
    return (int)YC_MACH2(YC_TRAP_PORT_DEALLOCATE, task, name);
}

YC_EXPORT int mach_port_mod_refs(yc_port_t task, yc_port_t name, yc_u32 right, int delta)
{
    return (int)YC_MACH4(YC_TRAP_PORT_MOD_REFS, task, name, right, (yc_intptr_t)delta);
}

YC_EXPORT int mach_port_move_member(yc_port_t task, yc_port_t member, yc_port_t after)
{
    return (int)YC_MACH3(YC_TRAP_PORT_MOVE_MEMBER, task, member, after);
}

YC_EXPORT int mach_port_insert_right(yc_port_t task, yc_port_t name, yc_port_t poly, yc_u32 poly_poly)
{
    return (int)YC_MACH4(YC_TRAP_PORT_INSERT_RIGHT, task, name, poly, poly_poly);
}

YC_EXPORT int mach_port_insert_member(yc_port_t task, yc_port_t name, yc_port_t pset)
{
    return (int)YC_MACH3(YC_TRAP_PORT_INSERT_MEMBER, task, name, pset);
}

YC_EXPORT int mach_port_extract_member(yc_port_t task, yc_port_t name, yc_port_t pset)
{
    return (int)YC_MACH3(YC_TRAP_PORT_EXTRACT_MEMBER, task, name, pset);
}

YC_EXPORT int mach_port_construct(yc_port_t task, void *options, yc_u64 context, yc_port_t *name)
{
    return (int)YC_MACH4(YC_TRAP_PORT_CONSTRUCT, task, options, context, name);
}

YC_EXPORT int mach_port_destruct(yc_port_t task, yc_port_t name, int srdelta, yc_u64 guard)
{
    return (int)YC_MACH4(YC_TRAP_PORT_DESTRUCT, task, name, (yc_intptr_t)srdelta, guard);
}

YC_EXPORT int mach_port_get_attributes(yc_port_t task, yc_port_t name, int flavor, void *info, yc_u32 *count)
{
    return (int)YC_MACH5(YC_TRAP_PORT_GET_ATTRIBUTES, task, name, (yc_intptr_t)flavor, info, count);
}

YC_EXPORT int mach_port_guard(yc_port_t task, yc_port_t name, yc_u64 guard, int strict)
{
    return (int)YC_MACH4(YC_TRAP_PORT_GUARD, task, name, guard, (yc_intptr_t)strict);
}

YC_EXPORT int mach_port_unguard(yc_port_t task, yc_port_t name, yc_u64 guard)
{
    return (int)YC_MACH3(YC_TRAP_PORT_UNGUARD, task, name, guard);
}

YC_EXPORT int mach_port_type(yc_port_t task, yc_port_t name, yc_u32 *ptype)
{
    return (int)YC_MACH3(YC_TRAP_PORT_TYPE, task, name, ptype);
}

YC_EXPORT int mach_port_request_notification(yc_port_t task, yc_port_t name, int msgid, yc_u32 sync,
                                             yc_port_t notify, yc_u32 notify_poly, yc_port_t *previous)
{
    return (int)yc_mach_trap(YC_TRAP_PORT_REQUEST_NOTIFICATION, task, name, (yc_uintptr_t)(yc_intptr_t)msgid, sync,
                             notify, notify_poly, (yc_uintptr_t)previous);
}

#define YC_MPG_STRICT 0x01u
#define YC_MPG_IMMOVABLE_RECEIVE 0x02u

YC_EXPORT int mach_port_guard_with_flags(yc_port_t task, yc_port_t name, yc_u64 guard, yc_u64 flags)
{
    if (flags & ~(yc_u64)(YC_MPG_STRICT | YC_MPG_IMMOVABLE_RECEIVE))
        return YC_KERN_INVALID_ARGUMENT;
    return mach_port_guard(task, name, guard, (flags & YC_MPG_STRICT) ? 1 : 0);
}

YC_EXPORT int mach_port_destroy(yc_port_t task, yc_port_t name)
{
    if (name == YC_MACH_PORT_NULL || name == YC_MACH_PORT_DEAD)
        return YC_KERN_SUCCESS;
    yc_u32 type = 0;
    int kr = mach_port_type(task, name, &type);
    if (kr != YC_KERN_SUCCESS)
        return kr;
    if (type & YC_MACH_PORT_TYPE_PORT_SET)
        return mach_port_mod_refs(task, name, YC_MACH_PORT_RIGHT_PORT_SET, -1);
    if (type & YC_MACH_PORT_TYPE_SEND_ONCE)
        return mach_port_mod_refs(task, name, YC_MACH_PORT_RIGHT_SEND_ONCE, -1);
    if (type & YC_MACH_PORT_TYPE_RECEIVE) {
        kr = mach_port_mod_refs(task, name, YC_MACH_PORT_RIGHT_RECEIVE, -1);
        if (kr != YC_KERN_SUCCESS)
            return kr;
    }
    for (yc_u32 i = 0; i <= 0x10000u; i++) {
        if (mach_port_type(task, name, &type) != YC_KERN_SUCCESS)
            return YC_KERN_SUCCESS;
        if (!(type & (YC_MACH_PORT_TYPE_SEND | YC_MACH_PORT_TYPE_DEAD_NAME)))
            return YC_KERN_SUCCESS;
        if (mach_port_deallocate(task, name) != YC_KERN_SUCCESS)
            return YC_KERN_SUCCESS;
    }
    return YC_KERN_SUCCESS;
}

YC_EXPORT int _kernelrpc_mach_port_allocate(yc_port_t task, yc_u32 right, yc_port_t *name)
{
    return mach_port_allocate(task, right, name);
}

YC_EXPORT int _kernelrpc_mach_port_deallocate(yc_port_t task, yc_port_t name)
{
    return mach_port_deallocate(task, name);
}

YC_EXPORT int _kernelrpc_mach_port_mod_refs(yc_port_t task, yc_port_t name, yc_u32 right, int delta)
{
    return mach_port_mod_refs(task, name, right, delta);
}

YC_EXPORT int _kernelrpc_mach_port_move_member(yc_port_t task, yc_port_t member, yc_port_t after)
{
    return mach_port_move_member(task, member, after);
}

YC_EXPORT int _kernelrpc_mach_port_insert_right(yc_port_t task, yc_port_t name, yc_port_t poly, yc_u32 poly_poly)
{
    return mach_port_insert_right(task, name, poly, poly_poly);
}

YC_EXPORT int _kernelrpc_mach_port_insert_member(yc_port_t task, yc_port_t name, yc_port_t pset)
{
    return mach_port_insert_member(task, name, pset);
}

YC_EXPORT int _kernelrpc_mach_port_extract_member(yc_port_t task, yc_port_t name, yc_port_t pset)
{
    return mach_port_extract_member(task, name, pset);
}

YC_EXPORT int _kernelrpc_mach_port_construct(yc_port_t task, void *options, yc_u64 context, yc_port_t *name)
{
    return mach_port_construct(task, options, context, name);
}

YC_EXPORT int _kernelrpc_mach_port_destruct(yc_port_t task, yc_port_t name, int srdelta, yc_u64 guard)
{
    return mach_port_destruct(task, name, srdelta, guard);
}

YC_EXPORT int _kernelrpc_mach_port_get_attributes(yc_port_t task, yc_port_t name, int flavor, void *info,
                                                  yc_u32 *count)
{
    return mach_port_get_attributes(task, name, flavor, info, count);
}

YC_EXPORT int _kernelrpc_mach_port_guard(yc_port_t task, yc_port_t name, yc_u64 guard, int strict)
{
    return mach_port_guard(task, name, guard, strict);
}

YC_EXPORT int _kernelrpc_mach_port_guard_with_flags(yc_port_t task, yc_port_t name, yc_u64 guard, yc_u64 flags)
{
    return mach_port_guard_with_flags(task, name, guard, flags);
}

YC_EXPORT int _kernelrpc_mach_port_unguard(yc_port_t task, yc_port_t name, yc_u64 guard)
{
    return mach_port_unguard(task, name, guard);
}

YC_EXPORT int _kernelrpc_mach_port_type(yc_port_t task, yc_port_t name, yc_u32 *ptype)
{
    return mach_port_type(task, name, ptype);
}

YC_EXPORT int _kernelrpc_mach_port_request_notification(yc_port_t task, yc_port_t name, int msgid, yc_u32 sync,
                                                        yc_port_t notify, yc_u32 notify_poly, yc_port_t *previous)
{
    return mach_port_request_notification(task, name, msgid, sync, notify, notify_poly, previous);
}

YC_EXPORT int _kernelrpc_mach_port_destroy(yc_port_t task, yc_port_t name)
{
    return mach_port_destroy(task, name);
}

YC_EXPORT int mach_vm_allocate(yc_port_t task, yc_u64 *address, yc_u64 size, int flags)
{
    return (int)YC_MACH4(YC_TRAP_VM_ALLOCATE, task, address, size, (yc_intptr_t)flags);
}

YC_EXPORT int mach_vm_deallocate(yc_port_t task, yc_u64 address, yc_u64 size)
{
    return (int)YC_MACH3(YC_TRAP_VM_DEALLOCATE, task, address, size);
}

YC_EXPORT int mach_vm_protect(yc_port_t task, yc_u64 address, yc_u64 size, int set_maximum, int new_protection)
{
    return (int)YC_MACH5(YC_TRAP_VM_PROTECT, task, address, size, (yc_intptr_t)set_maximum,
                         (yc_intptr_t)new_protection);
}

YC_EXPORT int mach_vm_purgable_control(yc_port_t task, yc_u64 address, int control, int *state)
{
    return (int)YC_MACH4(YC_TRAP_VM_PURGABLE_CONTROL, task, address, (yc_intptr_t)control, state);
}

YC_EXPORT int vm_allocate(yc_port_t task, yc_uintptr_t *address, yc_uintptr_t size, int flags)
{
    return mach_vm_allocate(task, (yc_u64 *)address, size, flags);
}

YC_EXPORT int vm_deallocate(yc_port_t task, yc_uintptr_t address, yc_uintptr_t size)
{
    return mach_vm_deallocate(task, address, size);
}

YC_EXPORT int vm_protect(yc_port_t task, yc_uintptr_t address, yc_uintptr_t size, int set_maximum,
                         int new_protection)
{
    return mach_vm_protect(task, address, size, set_maximum, new_protection);
}

YC_EXPORT int vm_purgable_control(yc_port_t task, yc_uintptr_t address, int control, int *state)
{
    return mach_vm_purgable_control(task, address, control, state);
}

typedef struct {
    yc_u32 tv_sec;
    int tv_nsec;
} yc_mach_timespec_t;

YC_EXPORT int semaphore_signal(yc_port_t semaphore)
{
    return (int)YC_MACH1(YC_TRAP_SEMAPHORE_SIGNAL, semaphore);
}

YC_EXPORT int semaphore_signal_all(yc_port_t semaphore)
{
    return (int)YC_MACH1(YC_TRAP_SEMAPHORE_SIGNAL_ALL, semaphore);
}

YC_EXPORT int semaphore_signal_thread(yc_port_t semaphore, yc_port_t thread)
{
    return (int)YC_MACH2(YC_TRAP_SEMAPHORE_SIGNAL_THREAD, semaphore, thread);
}

YC_EXPORT int semaphore_wait(yc_port_t semaphore)
{
    return (int)YC_MACH1(YC_TRAP_SEMAPHORE_WAIT, semaphore);
}

YC_EXPORT int semaphore_wait_signal(yc_port_t wait_semaphore, yc_port_t signal_semaphore)
{
    return (int)YC_MACH2(YC_TRAP_SEMAPHORE_WAIT_SIGNAL, wait_semaphore, signal_semaphore);
}

YC_EXPORT int semaphore_timedwait(yc_port_t semaphore, yc_mach_timespec_t wait_time)
{
    return (int)YC_MACH3(YC_TRAP_SEMAPHORE_TIMEDWAIT, semaphore, wait_time.tv_sec,
                         (yc_intptr_t)wait_time.tv_nsec);
}

YC_EXPORT int semaphore_timedwait_signal(yc_port_t wait_semaphore, yc_port_t signal_semaphore,
                                         yc_mach_timespec_t wait_time)
{
    return (int)YC_MACH4(YC_TRAP_SEMAPHORE_TIMEDWAIT_SIGNAL, wait_semaphore, signal_semaphore, wait_time.tv_sec,
                         (yc_intptr_t)wait_time.tv_nsec);
}

static yc_port_t yc_reply_port_no_tsd;
static yc_port_t yc_special_reply_port_no_tsd;

static yc_port_t cached_port_get(int slot, yc_port_t *fallback, long trap)
{
    yc_uintptr_t *tsd = yc_tsd_base();
    yc_port_t port = tsd ? (yc_port_t)tsd[slot] : *fallback;
    if (port == YC_MACH_PORT_NULL) {
        port = (yc_port_t)YC_MACH0(trap);
        if (tsd)
            tsd[slot] = port;
        else
            *fallback = port;
    }
    return port;
}

static yc_port_t cached_port_forget(int slot, yc_port_t *fallback, yc_port_t given)
{
    yc_uintptr_t *tsd = yc_tsd_base();
    yc_port_t port = tsd ? (yc_port_t)tsd[slot] : *fallback;
    if (tsd)
        tsd[slot] = 0;
    else
        *fallback = YC_MACH_PORT_NULL;
    return port != YC_MACH_PORT_NULL ? port : given;
}

static void cached_port_dealloc(int slot, yc_port_t *fallback, yc_port_t given)
{
    yc_port_t port = cached_port_forget(slot, fallback, given);
    if (port != YC_MACH_PORT_NULL)
        (void)mach_port_mod_refs(mach_task_self_, port, YC_MACH_PORT_RIGHT_RECEIVE, -1);
}

YC_EXPORT yc_port_t mig_get_reply_port(void)
{
    return cached_port_get(YC_TSD_MIG_REPLY, &yc_reply_port_no_tsd, YC_TRAP_REPLY_PORT);
}

YC_EXPORT void mig_dealloc_reply_port(yc_port_t reply_port)
{
    cached_port_dealloc(YC_TSD_MIG_REPLY, &yc_reply_port_no_tsd, reply_port);
}

YC_EXPORT void mig_put_reply_port(yc_port_t reply_port)
{
    (void)reply_port;
}

YC_EXPORT yc_port_t mig_get_special_reply_port(void)
{
    return cached_port_get(YC_TSD_MACH_SPECIAL_REPLY, &yc_special_reply_port_no_tsd, YC_TRAP_SPECIAL_REPLY_PORT);
}

#define YC_SRP_ALL 0
#define YC_SRP_RECEIVE_ONLY 1
#define YC_SRP_SEND_ONLY 2

YC_EXPORT int thread_destruct_special_reply_port(yc_port_t port, int rights)
{
    switch (rights) {
    case YC_SRP_ALL: {
        int kr = mach_port_destruct(mach_task_self_, port, -1, 0);
        if (kr != YC_KERN_SUCCESS)
            kr = mach_port_mod_refs(mach_task_self_, port, YC_MACH_PORT_RIGHT_RECEIVE, -1);
        return kr;
    }
    case YC_SRP_RECEIVE_ONLY:
        return mach_port_mod_refs(mach_task_self_, port, YC_MACH_PORT_RIGHT_RECEIVE, -1);
    case YC_SRP_SEND_ONLY:
        return mach_port_deallocate(mach_task_self_, port);
    default:
        return YC_KERN_INVALID_ARGUMENT;
    }
}

YC_EXPORT void mig_dealloc_special_reply_port(yc_port_t migport)
{
    yc_port_t port = cached_port_forget(YC_TSD_MACH_SPECIAL_REPLY, &yc_special_reply_port_no_tsd, migport);
    if (port != YC_MACH_PORT_NULL)
        (void)thread_destruct_special_reply_port(port, YC_SRP_ALL);
}

YC_EXPORT void mig_deallocate(yc_uintptr_t addr, yc_uintptr_t size)
{
    (void)vm_deallocate(mach_task_self_, addr, size);
}

static int mig_copy(char *dest, const char *src, int len, int zerofill)
{
    int i = 0;
    if (dest == YC_NULL || len <= 0)
        return 0;
    if (src != YC_NULL)
        while (i < len - 1 && src[i] != '\0') {
            dest[i] = src[i];
            i++;
        }
    dest[i++] = '\0';
    if (zerofill)
        for (int j = i; j < len; j++)
            dest[j] = '\0';
    return i;
}

YC_EXPORT int mig_strncpy(char *dest, const char *src, int len)
{
    return mig_copy(dest, src, len, 0);
}

YC_EXPORT int mig_strncpy_zerofill(char *dest, const char *src, int len)
{
    return mig_copy(dest, src, len, 1);
}

#define YC_HOST_BASIC_INFO 1
#define YC_HOST_BASIC_INFO_COUNT 12u
#define YC_HOST_BASIC_INFO_OLD_COUNT 5u
#define YC_HOST_SCHED_INFO 3
#define YC_HOST_SCHED_INFO_COUNT 2u
#define YC_HOST_PRIORITY_INFO 5
#define YC_HOST_PRIORITY_INFO_COUNT 8u

#define YC_CPU_TYPE_ARM64 0x0100000cu
#define YC_CPU_SUBTYPE_ARM64_ALL 0u
#define YC_GUEST_MEMORY_BYTES (1ull << 30)

static void yc_host_info_unimplemented(int flavor)
{
    char message[32];
    char digits[12];
    const char *prefix = "host_info (flavor ";
    for (int i = 0; i < 18; i++) message[i] = prefix[i];
    unsigned long long v = flavor < 0 ? 0ull - (unsigned long long)(long long)flavor : (unsigned long long)flavor;
    int n = 0;
    do { digits[n++] = (char)('0' + (v % 10)); v /= 10; } while (v != 0 && n < 11);
    char *p = message + 18;
    if (flavor < 0) *p++ = '-';
    while (n > 0) *p++ = digits[--n];
    *p++ = ')';
    *p = '\0';
    yc_unimplemented(message);
}

YC_EXPORT int host_info(yc_port_t host, int flavor, int *info, yc_u32 *count)
{
    (void)host;
    if (info == YC_NULL || count == YC_NULL)
        return YC_KERN_INVALID_ARGUMENT;
    if (flavor == YC_HOST_BASIC_INFO) {
        if (*count < YC_HOST_BASIC_INFO_OLD_COUNT)
            return YC_KERN_FAILURE;
        if (*count < YC_HOST_BASIC_INFO_COUNT) {
            info[0] = 1;
            info[1] = 1;
            info[2] = (int)(unsigned)YC_GUEST_MEMORY_BYTES;
            info[3] = (int)YC_CPU_TYPE_ARM64;
            info[4] = (int)YC_CPU_SUBTYPE_ARM64_ALL;
            *count = YC_HOST_BASIC_INFO_OLD_COUNT;
            return YC_KERN_SUCCESS;
        }
        info[0] = 1;
        info[1] = 1;
        info[2] = (int)(unsigned)YC_GUEST_MEMORY_BYTES;
        info[3] = (int)YC_CPU_TYPE_ARM64;
        info[4] = (int)YC_CPU_SUBTYPE_ARM64_ALL;
        info[5] = 0;
        info[6] = 1;
        info[7] = 1;
        info[8] = 1;
        info[9] = 1;
        info[10] = (int)(unsigned)(YC_GUEST_MEMORY_BYTES & 0xffffffffu);
        info[11] = (int)(unsigned)(YC_GUEST_MEMORY_BYTES >> 32);
        *count = YC_HOST_BASIC_INFO_COUNT;
        return YC_KERN_SUCCESS;
    }
    if (flavor == YC_HOST_SCHED_INFO) {
        if (*count < YC_HOST_SCHED_INFO_COUNT)
            return YC_KERN_FAILURE;
        info[0] = 10;
        info[1] = 10;
        *count = YC_HOST_SCHED_INFO_COUNT;
        return YC_KERN_SUCCESS;
    }
    if (flavor == YC_HOST_PRIORITY_INFO) {
        static const int prio[YC_HOST_PRIORITY_INFO_COUNT] = {80, 80, 64, 31, 0, 0, 0, 79};
        if (*count < YC_HOST_PRIORITY_INFO_COUNT)
            return YC_KERN_FAILURE;
        for (unsigned i = 0; i < YC_HOST_PRIORITY_INFO_COUNT; i++)
            info[i] = prio[i];
        *count = YC_HOST_PRIORITY_INFO_COUNT;
        return YC_KERN_SUCCESS;
    }
    yc_host_info_unimplemented(flavor);
    return YC_KERN_NOT_SUPPORTED;
}

YC_EXPORT int host_page_size(yc_port_t host, yc_uintptr_t *size)
{
    (void)host;
    if (size == YC_NULL)
        return YC_KERN_INVALID_ARGUMENT;
    *size = vm_kernel_page_size;
    return YC_KERN_SUCCESS;
}

YC_EXPORT yc_port_t host_self(void)
{
    return mach_host_self();
}

YC_EXPORT int _host_page_size(yc_port_t host, yc_uintptr_t *size)
{
    return host_page_size(host, size);
}

#define YC_VOUCHER_MACH_MSG_STATE_UNCHANGED ((void *)~(yc_uintptr_t)0)

YC_EXPORT int voucher_mach_msg_set(void *msg)
{
    const struct yc_libkernel_voucher_functions *v = yc_libkernel_voucher_fns;
    if (v != YC_NULL && v->voucher_mach_msg_set != YC_NULL)
        return v->voucher_mach_msg_set(msg);
    return 0;
}

YC_EXPORT void voucher_mach_msg_clear(void *msg)
{
    const struct yc_libkernel_voucher_functions *v = yc_libkernel_voucher_fns;
    if (v != YC_NULL && v->voucher_mach_msg_clear != YC_NULL)
        v->voucher_mach_msg_clear(msg);
}

YC_EXPORT void *voucher_mach_msg_adopt(void *msg)
{
    const struct yc_libkernel_voucher_functions *v = yc_libkernel_voucher_fns;
    if (v != YC_NULL && v->voucher_mach_msg_adopt != YC_NULL)
        return v->voucher_mach_msg_adopt(msg);
    return YC_VOUCHER_MACH_MSG_STATE_UNCHANGED;
}

YC_EXPORT void voucher_mach_msg_revert(void *state)
{
    const struct yc_libkernel_voucher_functions *v = yc_libkernel_voucher_fns;
    if (v != YC_NULL && v->voucher_mach_msg_revert != YC_NULL)
        v->voucher_mach_msg_revert(state);
}

#define YC_PRIV_ROUTINE(n) ((long)(0x79632000u + (n)))
#define YC_PRIV_HOST_GET_CLOCK_SERVICE 1
#define YC_PRIV_CLOCK_GET_TIME 2
#define YC_PRIV_SEMAPHORE_CREATE 3
#define YC_PRIV_SEMAPHORE_DESTROY 4
#define YC_PRIV_TASK_GET_SPECIAL_PORT 5
#define YC_PRIV_TASK_SET_SPECIAL_PORT 6
#define YC_PRIV_HOST_CREATE_MACH_VOUCHER 7
#define YC_PRIV_MACH_PORTS_REGISTER3 8
#define YC_PRIV_MACH_PORTS_LOOKUP3 9
#define YC_PRIV_MAKE_MEMORY_ENTRY 10
#define YC_PRIV_VM_MAP_OBJECT 11

YC_EXPORT int mach_make_memory_entry_64(yc_port_t task, yc_u64 *size, yc_u64 offset, int permission,
                                        yc_port_t *object_handle, yc_port_t parent_entry)
{
    return (int)yc_mach_trap(YC_PRIV_ROUTINE(YC_PRIV_MAKE_MEMORY_ENTRY), task, (yc_uintptr_t)size, offset,
                             (yc_uintptr_t)(unsigned)permission, (yc_uintptr_t)object_handle, parent_entry, 0);
}

YC_EXPORT int mach_make_memory_entry(yc_port_t task, yc_uintptr_t *size, yc_uintptr_t offset, int permission,
                                     yc_port_t *object_handle, yc_port_t parent_entry)
{
    return mach_make_memory_entry_64(task, (yc_u64 *)size, offset, permission, object_handle, parent_entry);
}

YC_EXPORT int mach_vm_map(yc_port_t target, yc_u64 *address, yc_u64 size, yc_u64 mask, int flags, yc_port_t object,
                          yc_u64 offset, int copy, int cur, int max, int inherit)
{
    if (object == 0 && offset == 0)
        return (int)yc_mach_trap(-15, target, (yc_uintptr_t)address, size, mask, (yc_uintptr_t)(unsigned)flags,
                                 (yc_uintptr_t)(unsigned)cur, 0);
    yc_u64 block[6] = {object, offset, (yc_u64)(unsigned)copy, (yc_u64)(unsigned)cur, (yc_u64)(unsigned)max,
                       (yc_u64)(unsigned)inherit};
    return (int)yc_mach_trap(YC_PRIV_ROUTINE(YC_PRIV_VM_MAP_OBJECT), target, (yc_uintptr_t)address, size, mask,
                             (yc_uintptr_t)(unsigned)flags, (yc_uintptr_t)block, 0);
}

YC_EXPORT int vm_map(yc_port_t target, yc_uintptr_t *address, yc_uintptr_t size, yc_uintptr_t mask, int flags,
                     yc_port_t object, yc_uintptr_t offset, int copy, int cur, int max, int inherit)
{
    return mach_vm_map(target, (yc_u64 *)address, size, mask, flags, object, offset, copy, cur, max, inherit);
}

YC_EXPORT int host_get_clock_service(yc_port_t host, int clock_id, yc_port_t *clock_serv)
{
    return (int)YC_MACH3(YC_PRIV_ROUTINE(YC_PRIV_HOST_GET_CLOCK_SERVICE), host, (yc_intptr_t)clock_id,
                         clock_serv);
}

YC_EXPORT int clock_get_time(yc_port_t clock_serv, yc_mach_timespec_t *cur_time)
{
    return (int)YC_MACH2(YC_PRIV_ROUTINE(YC_PRIV_CLOCK_GET_TIME), clock_serv, cur_time);
}

YC_EXPORT int semaphore_create(yc_port_t task, yc_port_t *semaphore, int policy, int value)
{
    return (int)YC_MACH4(YC_PRIV_ROUTINE(YC_PRIV_SEMAPHORE_CREATE), task, semaphore, (yc_intptr_t)policy,
                         (yc_intptr_t)value);
}

YC_EXPORT int semaphore_destroy(yc_port_t task, yc_port_t semaphore)
{
    return (int)YC_MACH2(YC_PRIV_ROUTINE(YC_PRIV_SEMAPHORE_DESTROY), task, semaphore);
}

YC_EXPORT int task_get_special_port(yc_port_t task, int which_port, yc_port_t *special_port)
{
    return (int)YC_MACH3(YC_PRIV_ROUTINE(YC_PRIV_TASK_GET_SPECIAL_PORT), task, (yc_intptr_t)which_port,
                         special_port);
}

YC_EXPORT int task_set_special_port(yc_port_t task, int which_port, yc_port_t special_port)
{
    return (int)YC_MACH3(YC_PRIV_ROUTINE(YC_PRIV_TASK_SET_SPECIAL_PORT), task, (yc_intptr_t)which_port,
                         special_port);
}

#define YC_TASK_PORT_REGISTER_MAX 3u
#define YC_VM_FLAGS_ANYWHERE 1

YC_EXPORT int mach_ports_register(yc_port_t task, const yc_port_t *ports, yc_u32 count)
{
    yc_port_t p[YC_TASK_PORT_REGISTER_MAX] = {YC_MACH_PORT_NULL, YC_MACH_PORT_NULL, YC_MACH_PORT_NULL};
    if (count > YC_TASK_PORT_REGISTER_MAX || (count > 0 && ports == YC_NULL))
        return YC_KERN_INVALID_ARGUMENT;
    for (yc_u32 i = 0; i < count; i++)
        p[i] = ports[i];
    return (int)YC_MACH4(YC_PRIV_ROUTINE(YC_PRIV_MACH_PORTS_REGISTER3), task, p[0], p[1], p[2]);
}

YC_EXPORT int mach_ports_lookup(yc_port_t task, yc_port_t **ports, yc_u32 *count)
{
    if (ports == YC_NULL || count == YC_NULL)
        return YC_KERN_INVALID_ARGUMENT;
    yc_uintptr_t size = (YC_TASK_PORT_REGISTER_MAX * sizeof(yc_port_t) + vm_page_size - 1) & ~(vm_page_size - 1);
    yc_uintptr_t addr = 0;
    int kr = vm_allocate(mach_task_self_, &addr, size, YC_VM_FLAGS_ANYWHERE);
    if (kr != YC_KERN_SUCCESS)
        return kr;
    yc_port_t *a = (yc_port_t *)addr;
    kr = (int)YC_MACH4(YC_PRIV_ROUTINE(YC_PRIV_MACH_PORTS_LOOKUP3), task, &a[0], &a[1], &a[2]);
    if (kr != YC_KERN_SUCCESS) {
        (void)vm_deallocate(mach_task_self_, addr, size);
        return kr;
    }
    *ports = a;
    *count = YC_TASK_PORT_REGISTER_MAX;
    return YC_KERN_SUCCESS;
}

YC_EXPORT int host_create_mach_voucher(yc_port_t host, const void *recipes, yc_u32 recipes_size,
                                       yc_port_t *voucher)
{
    return (int)YC_MACH4(YC_PRIV_ROUTINE(YC_PRIV_HOST_CREATE_MACH_VOUCHER), host, recipes, recipes_size, voucher);
}

YC_EXPORT int _kernelrpc_host_create_mach_voucher(yc_port_t host, const void *recipes, yc_u32 recipes_size,
                                                  yc_port_t *voucher)
{
    return host_create_mach_voucher(host, recipes, recipes_size, voucher);
}

YC_EXPORT int mach_voucher_extract_attr_recipe(yc_port_t voucher, yc_u32 key, void *recipe, yc_u32 *recipe_size)
{
    return (int)YC_MACH4(YC_TRAP_VOUCHER_EXTRACT_ATTR_RECIPE, voucher, key, recipe, recipe_size);
}

YC_EXPORT int _kernelrpc_mach_voucher_extract_attr_recipe(yc_port_t voucher, yc_u32 key, void *recipe,
                                                          yc_u32 *recipe_size)
{
    return mach_voucher_extract_attr_recipe(voucher, key, recipe, recipe_size);
}

YC_EXPORT int mach_voucher_deallocate(yc_port_t voucher)
{
    return mach_port_deallocate(mach_task_self_, voucher);
}

YC_EXPORT int mach_voucher_attr_command(yc_port_t voucher, yc_u32 key, yc_u32 command, const void *in_content,
                                        yc_u32 in_size, void *out_content, yc_u32 *out_size)
{
    (void)voucher;
    (void)key;
    (void)command;
    (void)in_content;
    (void)in_size;
    (void)out_content;
    (void)out_size;
    return YC_MACH_SEND_INVALID_DEST;
}

YC_EXPORT int task_info(yc_port_t task, int flavor, void *task_info_out, yc_u32 *task_info_outCnt)
{
    return (int)YC_MACH4(0x79630006L, task, (yc_uintptr_t)(unsigned)flavor, task_info_out, task_info_outCnt);
}

#define YC_PRIV_VM_REMAP 12
#define YC_PRIV_TASK_THREADS 13

static int yc_vm_remap(yc_port_t target, yc_u64 *address, yc_u64 size, yc_u64 mask, int flags, yc_port_t src_task,
                       yc_u64 src_address, int copy, int *cur, int *max, int inherit, int is_new)
{
    yc_u64 block[7] = {src_task, src_address, (yc_u64)(unsigned)copy, (yc_u64)(yc_uintptr_t)cur,
                       (yc_u64)(yc_uintptr_t)max, (yc_u64)(unsigned)inherit, (yc_u64)(unsigned)is_new};
    return (int)yc_mach_trap(YC_PRIV_ROUTINE(YC_PRIV_VM_REMAP), target, (yc_uintptr_t)address, size, mask,
                             (yc_uintptr_t)(unsigned)flags, (yc_uintptr_t)block, 0);
}

YC_EXPORT int mach_vm_remap(yc_port_t target, yc_u64 *address, yc_u64 size, yc_u64 mask, int flags,
                            yc_port_t src_task, yc_u64 src_address, int copy, int *cur, int *max, int inherit)
{
    return yc_vm_remap(target, address, size, mask, flags, src_task, src_address, copy, cur, max, inherit, 0);
}

YC_EXPORT int mach_vm_remap_new(yc_port_t target, yc_u64 *address, yc_u64 size, yc_u64 mask, int flags,
                                yc_port_t src_task, yc_u64 src_address, int copy, int *cur, int *max, int inherit)
{
    return yc_vm_remap(target, address, size, mask, flags, src_task, src_address, copy, cur, max, inherit, 1);
}

YC_EXPORT int vm_remap(yc_port_t target, yc_uintptr_t *address, yc_uintptr_t size, yc_uintptr_t mask, int flags,
                       yc_port_t src_task, yc_uintptr_t src_address, int copy, int *cur, int *max, int inherit)
{
    return mach_vm_remap(target, (yc_u64 *)address, size, mask, flags, src_task, src_address, copy, cur, max, inherit);
}

YC_EXPORT int vm_remap_new(yc_port_t target, yc_uintptr_t *address, yc_uintptr_t size, yc_uintptr_t mask, int flags,
                           yc_port_t src_task, yc_uintptr_t src_address, int copy, int *cur, int *max, int inherit)
{
    return mach_vm_remap_new(target, (yc_u64 *)address, size, mask, flags, src_task, src_address, copy, cur, max,
                             inherit);
}

YC_EXPORT int task_threads(yc_port_t task, yc_port_t **act_list, yc_u32 *act_list_count)
{
    return (int)YC_MACH3(YC_PRIV_ROUTINE(YC_PRIV_TASK_THREADS), task, act_list, act_list_count);
}

YC_EXPORT int mach_port_get_context(yc_port_t task, yc_port_t name, yc_u64 *context)
{
    return (int)YC_MACH3(YC_PRIV_ROUTINE(14), task, name, context);
}

YC_EXPORT int mach_port_set_context(yc_port_t task, yc_port_t name, yc_u64 context)
{
    return (int)YC_MACH3(YC_PRIV_ROUTINE(15), task, name, context);
}

YC_EXPORT int host_get_io_main(yc_port_t host, yc_port_t *io_main)
{
    return (int)YC_MACH3(YC_PRIV_ROUTINE(16), host, io_main, 0);
}

YC_EXPORT int host_get_io_master(yc_port_t host, yc_port_t *io_master)
{
    return host_get_io_main(host, io_master);
}

#define YC_THREAD_STATE_RETRY 0x79630000L
YC_EXPORT int thread_get_state(yc_port_t thread, int flavor, yc_u32 *state, yc_u32 *count)
{
    for (unsigned tries = 0; tries < 1000000u; tries++) {
        yc_intptr_t kr = (yc_intptr_t)yc_mach_trap(YC_PRIV_ROUTINE(17), thread, (yc_uintptr_t)(unsigned)flavor,
                                                   (yc_uintptr_t)state, (yc_uintptr_t)count, 0, 0, 0);
        if (kr != YC_THREAD_STATE_RETRY)
            return (int)kr;
    }
    return 5;
}

#define YC_PRIV_THREAD_SUSPEND 0x79630020L
#define YC_PRIV_THREAD_RESUME 0x79630021L
#define YC_PRIV_THREAD_ABORT 0x79630022L
#define YC_PRIV_THREAD_SET_STATE 0x79630023L
#define YC_PRIV_TASK_SUSPEND 0x79630024L
#define YC_PRIV_TASK_RESUME 0x79630025L

YC_EXPORT int thread_suspend(yc_port_t thread)
{
    return (int)YC_MACH3(YC_PRIV_THREAD_SUSPEND, thread, 0, 0);
}

YC_EXPORT int thread_resume(yc_port_t thread)
{
    return (int)YC_MACH3(YC_PRIV_THREAD_RESUME, thread, 0, 0);
}

YC_EXPORT int thread_abort(yc_port_t thread)
{
    return (int)YC_MACH3(YC_PRIV_THREAD_ABORT, thread, 0, 0);
}

YC_EXPORT int thread_abort_safely(yc_port_t thread)
{
    return (int)YC_MACH3(YC_PRIV_THREAD_ABORT, thread, 1, 0);
}

YC_EXPORT int thread_set_state(yc_port_t thread, int flavor, const yc_u32 *state, yc_u32 count)
{
    return (int)yc_mach_trap(YC_PRIV_THREAD_SET_STATE, thread, (yc_uintptr_t)(unsigned)flavor, (yc_uintptr_t)state,
                             (yc_uintptr_t)count, 0, 0, 0);
}

YC_EXPORT int task_suspend(yc_port_t task)
{
    return (int)YC_MACH3(YC_PRIV_TASK_SUSPEND, task, 0, 0);
}

YC_EXPORT int task_resume(yc_port_t task)
{
    return (int)YC_MACH3(YC_PRIV_TASK_RESUME, task, 0, 0);
}

YC_EXPORT int thread_get_exception_ports(yc_port_t thread, yc_u32 mask, yc_u32 *masks, yc_u32 *count,
                                         yc_port_t *handlers, yc_u32 *behaviors, yc_u32 *flavors)
{
    return (int)yc_mach_trap(YC_PRIV_ROUTINE(18), thread, mask, (yc_uintptr_t)masks, (yc_uintptr_t)count,
                             (yc_uintptr_t)handlers, (yc_uintptr_t)behaviors, (yc_uintptr_t)flavors);
}

YC_EXPORT int thread_set_exception_ports(yc_port_t thread, yc_u32 mask, yc_port_t port, int behavior, int flavor)
{
    return (int)yc_mach_trap(YC_PRIV_ROUTINE(19), thread, mask, port, (yc_uintptr_t)(unsigned)behavior,
                             (yc_uintptr_t)(unsigned)flavor, 0, 0);
}

YC_EXPORT int thread_swap_exception_ports(yc_port_t thread, yc_u32 mask, yc_port_t port, int behavior, int flavor,
                                          yc_u32 *masks, yc_u32 *count, yc_port_t *handlers, yc_u32 *behaviors,
                                          yc_u32 *flavors)
{
    int kr = thread_get_exception_ports(thread, mask, masks, count, handlers, behaviors, flavors);
    if (kr != 0)
        return kr;
    kr = thread_set_exception_ports(thread, mask, port, behavior, flavor);
    if (kr != 0) {
        for (yc_u32 i = 0; i < *count; i++)
            if (handlers[i] != YC_MACH_PORT_NULL && handlers[i] != YC_MACH_PORT_DEAD)
                (void)mach_port_deallocate(mach_task_self_, handlers[i]);
        *count = 0;
    }
    return kr;
}

YC_EXPORT int mach_vm_read(yc_port_t task, yc_u64 address, yc_u64 size, yc_uintptr_t *data, yc_u32 *count)
{
    return (int)yc_mach_trap(YC_PRIV_ROUTINE(20), task, (yc_uintptr_t)address, (yc_uintptr_t)size,
                             (yc_uintptr_t)data, (yc_uintptr_t)count, 0, 0);
}

YC_EXPORT int vm_read(yc_port_t task, yc_uintptr_t address, yc_size_t size, yc_uintptr_t *data, yc_u32 *count)
{
    return mach_vm_read(task, address, size, data, count);
}

#define YC_PRIV_VM_REGION 21

YC_EXPORT int mach_vm_region(yc_port_t task, yc_u64 *address, yc_u64 *size, int flavor, int *info, yc_u32 *count,
                             yc_port_t *object_name)
{
    return (int)yc_mach_trap(YC_PRIV_ROUTINE(YC_PRIV_VM_REGION), task, (yc_uintptr_t)address, (yc_uintptr_t)size,
                             (yc_uintptr_t)(unsigned)flavor, (yc_uintptr_t)info, (yc_uintptr_t)count,
                             (yc_uintptr_t)object_name);
}

YC_EXPORT int vm_region_64(yc_port_t task, yc_uintptr_t *address, yc_size_t *size, int flavor, int *info, yc_u32 *count,
                           yc_port_t *object_name)
{
    return mach_vm_region(task, (yc_u64 *)address, (yc_u64 *)size, flavor, info, count, object_name);
}

#define YC_PRIV_VM_COPY 0x79630004L

YC_EXPORT int mach_vm_copy(yc_port_t task, yc_u64 source, yc_u64 size, yc_u64 dest)
{
    if (task != mach_task_self_)
        return YC_KERN_INVALID_ARGUMENT;
    return (int)YC_MACH4(YC_PRIV_VM_COPY, task, (yc_uintptr_t)source, (yc_uintptr_t)size, (yc_uintptr_t)dest);
}

YC_EXPORT int vm_copy(yc_port_t task, yc_uintptr_t source, yc_size_t size, yc_uintptr_t dest)
{
    return mach_vm_copy(task, source, size, dest);
}

YC_EXPORT int mach_vm_read_overwrite(yc_port_t task, yc_u64 address, yc_u64 size, yc_u64 data, yc_u64 *outsize)
{
    int kr = mach_vm_copy(task, address, size, data);
    if (kr == 0 && outsize != YC_NULL)
        *outsize = size;
    return kr;
}

YC_EXPORT int vm_read_overwrite(yc_port_t task, yc_uintptr_t address, yc_size_t size, yc_uintptr_t data,
                                yc_size_t *outsize)
{
    yc_u64 out = 0;
    int kr = mach_vm_read_overwrite(task, address, size, data, &out);
    if (kr == 0 && outsize != YC_NULL)
        *outsize = (yc_size_t)out;
    return kr;
}
