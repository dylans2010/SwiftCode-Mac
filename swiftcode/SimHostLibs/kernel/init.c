#include "yc_kernel.h"

YC_HIDDEN const struct yc_libkernel_functions *yc_libkernel_fns;
YC_HIDDEN const struct yc_libkernel_string_functions *yc_libkernel_string_fns;
YC_HIDDEN const struct yc_libkernel_voucher_functions *yc_libkernel_voucher_fns;

static void *(*yc_dlsym)(void *, const char *);

static yc_port_t yc_task_reply_port;
static int yc_mach_init_done;

static void set_page_triple(yc_u8 shift, int *shift_var, yc_uintptr_t *size_var, yc_uintptr_t *mask_var)
{
    if (shift < 12 || shift > 16)
        return;
    *shift_var = shift;
    *size_var = (yc_uintptr_t)1 << shift;
    *mask_var = *size_var - 1;
}

YC_EXPORT int mach_init(void)
{
    if (yc_mach_init_done)
        return 0;
    yc_mach_init_done = 1;

    yc_port_t task = (yc_port_t)YC_MACH0(YC_TRAP_TASK_SELF);
    if (task != YC_MACH_PORT_NULL)
        mach_task_self_ = task;
    yc_task_reply_port = (yc_port_t)YC_MACH0(YC_TRAP_REPLY_PORT);

    yc_port_t bootstrap = YC_MACH_PORT_NULL;
    if (task_get_special_port(mach_task_self_, YC_TASK_BOOTSTRAP_PORT, &bootstrap) == YC_KERN_SUCCESS)
        bootstrap_port = bootstrap;

    set_page_triple(yc_commpage_u8(YC_COMM_KERNEL_PAGE_SHIFT), &vm_kernel_page_shift, &vm_kernel_page_size,
                    &vm_kernel_page_mask);
    set_page_triple(yc_commpage_u8(YC_COMM_USER_PAGE_SHIFT_64), &vm_page_shift, &vm_page_size, &vm_page_mask);
    return 0;
}

YC_EXPORT void __libkernel_init(const struct yc_libkernel_functions *fns, const char **envp, const char **apple,
                                const void *vars)
{
    (void)envp;
    (void)apple;
    (void)vars;
    if (fns != YC_NULL) {
        yc_libkernel_fns = fns;
        if (fns->version >= 1 && fns->dlsym != YC_NULL)
            yc_dlsym = fns->dlsym;
    }
    mach_init();
}

YC_EXPORT int __libkernel_platform_init(const struct yc_libkernel_string_functions *fns)
{
    if (fns != YC_NULL)
        yc_libkernel_string_fns = fns;
    return 0;
}

YC_EXPORT int __libkernel_voucher_init(const struct yc_libkernel_voucher_functions *fns)
{
    if (fns != YC_NULL)
        yc_libkernel_voucher_fns = fns;
    return YC_KERN_SUCCESS;
}

YC_EXPORT void __libkernel_init_late(const void *config)
{
    (void)config;
}

YC_EXPORT void __libkernel_init_after_boot_tasks(const void *config)
{
    (void)config;
}

YC_EXPORT void _init_cpu_capabilities(void)
{
}

YC_EXPORT yc_u64 _get_cpu_capabilities(void)
{
    return yc_commpage_u64(YC_COMM_CPU_CAPABILITIES64);
}

YC_HIDDEN void *yc_kernel_dlsym(void *handle, const char *name)
{
    return yc_dlsym ? yc_dlsym(handle, name) : YC_NULL;
}

YC_HIDDEN yc_port_t yc_kernel_task_reply_port(void)
{
    return yc_task_reply_port;
}
