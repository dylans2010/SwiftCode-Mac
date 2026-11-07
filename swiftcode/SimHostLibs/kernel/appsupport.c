#include "yc_kernel.h"

#define YC_PRIV_ROUTINE(n) ((long)(0x79632000u + (n)))
#define YC_PRIV_THREAD_INFO 0x30

YC_EXPORT int thread_info(yc_port_t thread, yc_u32 flavor, int *info, yc_u32 *count)
{
    if (info == YC_NULL || count == YC_NULL)
        return YC_KERN_INVALID_ARGUMENT;
    return (int)yc_mach_trap(YC_PRIV_ROUTINE(YC_PRIV_THREAD_INFO), thread, flavor, (yc_uintptr_t)info,
                             (yc_uintptr_t)count, 0, 0, 0);
}

#define YC_THREAD_EXTENDED_POLICY 1
#define YC_THREAD_TIME_CONSTRAINT_POLICY 2
#define YC_THREAD_PRECEDENCE_POLICY 3
#define YC_THREAD_AFFINITY_POLICY 4
#define YC_THREAD_BACKGROUND_POLICY 5
#define YC_THREAD_LATENCY_QOS_POLICY 7
#define YC_THREAD_THROUGHPUT_QOS_POLICY 8
#define YC_THREAD_TIME_CONSTRAINT_WITH_PRIORITY_POLICY 10

static yc_u32 yc_policy_count(int flavor)
{
    switch (flavor) {
    case YC_THREAD_EXTENDED_POLICY: return 1;
    case YC_THREAD_TIME_CONSTRAINT_POLICY: return 4;
    case YC_THREAD_PRECEDENCE_POLICY: return 1;
    case YC_THREAD_AFFINITY_POLICY: return 1;
    case YC_THREAD_BACKGROUND_POLICY: return 1;
    case YC_THREAD_LATENCY_QOS_POLICY: return 1;
    case YC_THREAD_THROUGHPUT_QOS_POLICY: return 1;
    case YC_THREAD_TIME_CONSTRAINT_WITH_PRIORITY_POLICY: return 5;
    default: return 0;
    }
}

YC_EXPORT int thread_policy_set(yc_port_t thread, int flavor, const int *info, yc_u32 count)
{
    yc_u32 need = yc_policy_count(flavor);
    if (thread == 0 || need == 0 || info == YC_NULL || count < need)
        return YC_KERN_INVALID_ARGUMENT;
    return YC_KERN_SUCCESS;
}

YC_EXPORT int _kernelrpc_thread_policy_set(yc_port_t thread, int flavor, const int *info, yc_u32 count)
{
    return thread_policy_set(thread, flavor, info, count);
}

YC_EXPORT int thread_policy_get(yc_port_t thread, int flavor, int *info, yc_u32 *count, int *get_default)
{
    yc_u32 need = yc_policy_count(flavor);
    if (thread == 0 || need == 0 || info == YC_NULL || count == YC_NULL || *count < need)
        return YC_KERN_INVALID_ARGUMENT;
    for (yc_u32 i = 0; i < need; i++)
        info[i] = 0;
    if (flavor == YC_THREAD_EXTENDED_POLICY) {
        info[0] = 1;
    } else if (flavor == YC_THREAD_TIME_CONSTRAINT_POLICY || flavor == YC_THREAD_TIME_CONSTRAINT_WITH_PRIORITY_POLICY) {
        struct yc_mach_timebase_info tb = {1, 1};
        YC_KFN(mach_timebase_info)(&tb);
        yc_u64 ms = tb.numer ? (1000000ull * tb.denom) / tb.numer : 1000000ull;
        info[1] = (int)(yc_u32)(5 * ms);
        info[2] = (int)(yc_u32)(10 * ms);
        info[3] = 1;
    }
    *count = need;
    if (get_default != YC_NULL)
        *get_default = 1;
    return YC_KERN_SUCCESS;
}

#define YC_HOST_LOAD_INFO 1
#define YC_HOST_VM_INFO 2
#define YC_HOST_CPU_LOAD_INFO 3
#define YC_HOST_VM_INFO64 4
#define YC_GUEST_PAGES 65536u

static int yc_host_statistics(int flavor, int *info, yc_u32 *count, int wide)
{
    if (info == YC_NULL || count == YC_NULL)
        return YC_KERN_INVALID_ARGUMENT;
    yc_u32 need;
    switch (flavor) {
    case YC_HOST_LOAD_INFO: need = 6; break;
    case YC_HOST_VM_INFO: need = 15; break;
    case YC_HOST_CPU_LOAD_INFO: need = 4; break;
    case YC_HOST_VM_INFO64: need = wide ? 38 : 0; break;
    default: need = 0; break;
    }
    if (need == 0)
        return YC_KERN_INVALID_ARGUMENT;
    if (*count < need)
        return YC_KERN_FAILURE;
    for (yc_u32 i = 0; i < need; i++)
        info[i] = 0;
    if (flavor == YC_HOST_VM_INFO || flavor == YC_HOST_VM_INFO64) {
        info[0] = (int)(YC_GUEST_PAGES / 2);
        info[1] = (int)(YC_GUEST_PAGES / 4);
        info[2] = (int)(YC_GUEST_PAGES / 8);
        info[3] = (int)(YC_GUEST_PAGES / 8);
    } else if (flavor == YC_HOST_CPU_LOAD_INFO) {
        struct yc_mach_timebase_info tb = {1, 1};
        YC_KFN(mach_timebase_info)(&tb);
        yc_u64 ns = YC_KFN(mach_absolute_time)();
        if (tb.denom)
            ns = ns / tb.denom * tb.numer;
        info[2] = (int)(yc_u32)(ns / 10000000ull);
    }
    *count = need;
    return YC_KERN_SUCCESS;
}

YC_EXPORT int host_statistics(yc_port_t host, int flavor, int *info, yc_u32 *count)
{
    (void)host;
    return yc_host_statistics(flavor, info, count, 0);
}

YC_EXPORT int host_statistics64(yc_port_t host, int flavor, int *info, yc_u32 *count)
{
    (void)host;
    return yc_host_statistics(flavor, info, count, 1);
}

YC_EXPORT int proc_set_cpumon_params(int pid, int percentage, int interval)
{
    (void)pid; (void)percentage; (void)interval;
    return 0;
}

YC_EXPORT int proc_set_cpumon_params_fatal(int pid, int percentage, int interval)
{
    (void)pid; (void)percentage; (void)interval;
    return 0;
}

YC_EXPORT int proc_get_cpumon_params(int pid, int *percentage, int *interval)
{
    (void)pid;
    if (percentage != YC_NULL) *percentage = 0;
    if (interval != YC_NULL) *interval = 0;
    return 0;
}

YC_EXPORT int proc_set_cpumon_defaults(int pid) { (void)pid; return 0; }
YC_EXPORT int proc_resume_cpumon(int pid) { (void)pid; return 0; }
YC_EXPORT int proc_disable_cpumon(int pid) { (void)pid; return 0; }

YC_EXPORT int proc_set_wakemon_params(int pid, int rate_hz, int flags)
{
    (void)pid; (void)rate_hz; (void)flags;
    return 0;
}

YC_EXPORT int proc_get_wakemon_params(int pid, int *rate_hz, int *flags)
{
    (void)pid;
    if (rate_hz != YC_NULL) *rate_hz = 0;
    if (flags != YC_NULL) *flags = 0;
    return 0;
}

YC_EXPORT int proc_set_wakemon_defaults(int pid) { (void)pid; return 0; }
YC_EXPORT int proc_disable_wakemon(int pid) { (void)pid; return 0; }

YC_EXPORT int proc_setcpu_percentage(int pid, int action, int percentage)
{
    (void)pid; (void)action; (void)percentage;
    return 0;
}

YC_EXPORT int proc_clear_cpulimits(int pid) { (void)pid; return 0; }

YC_EXPORT int proc_setthread_cpupercent(yc_u8 percentage, yc_u32 ms_refill)
{
    (void)percentage; (void)ms_refill;
    return 0;
}

YC_EXPORT int task_create_identity_token(yc_port_t task, yc_port_t *token)
{
    if (token == YC_NULL || task == 0)
        return YC_KERN_INVALID_ARGUMENT;
    (void)mach_port_mod_refs(mach_task_self_, task, 0 , 1);
    *token = task;
    return 0;
}

YC_EXPORT int task_identity_token_get_task_port(yc_port_t token, int flavor, yc_port_t *task_port)
{
    if (task_port == YC_NULL || token == 0 || flavor < 0 || flavor > 3)
        return YC_KERN_INVALID_ARGUMENT;
    (void)mach_port_mod_refs(mach_task_self_, token, 0 , 1);
    *task_port = token;
    return 0;
}
