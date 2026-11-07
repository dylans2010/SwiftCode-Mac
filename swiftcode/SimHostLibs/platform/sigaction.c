#include "yc_platform.h"

struct yc_user_sigaction {
    void *handler;
    yc_u32 mask;
    int flags;
};
_Static_assert(sizeof(struct yc_user_sigaction) == 16, "struct sigaction is 16 bytes");

struct yc_kernel_sigaction {
    void *handler;
    void *tramp;
    yc_u32 mask;
    int flags;
};
_Static_assert(sizeof(struct yc_kernel_sigaction) == 24, "struct __sigaction is 24 bytes");

#if defined(YC_HOST_TEST) || !defined(__aarch64__)
YC_HIDDEN void yc_sigtramp(void)
{
}
#else
YC_HIDDEN void yc_sigtramp(void);
__asm__(".section __TEXT,__text,regular,pure_instructions\n"
        ".private_extern _yc_sigtramp\n"
        ".p2align 2\n"
        "_yc_sigtramp:\n"
        "    mov x19, x4\n"
        "    mov x20, x1\n"
        "    mov x21, x5\n"
        "    mov x16, x0\n"
        "    mov w0, w2\n"
        "    mov x1, x3\n"
        "    mov x2, x4\n"
        "    blr x16\n"
        "    mov x0, x19\n"
        "    mov w1, w20\n"
        "    mov x2, x21\n"
        "    mov x16, #184\n"
        "    svc #0x80\n"
        "    brk #0x7965\n");
#endif

YC_EXPORT int YC_FN(__platform_sigaction)(int sig, const struct yc_user_sigaction *nsv,
                                          struct yc_user_sigaction *osv)
{
    struct yc_kernel_sigaction ksa;
    struct yc_kernel_sigaction *kp = YC_NULL;
    if (nsv != YC_NULL) {
        ksa.handler = nsv->handler;
        ksa.tramp = (void *)yc_sigtramp;
        ksa.mask = nsv->mask;
        ksa.flags = nsv->flags;
        kp = &ksa;
    }
    return YC_KFN(__sigaction)(sig, kp, osv);
}
