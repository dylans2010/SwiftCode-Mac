#ifndef YC_KERNEL_API_H
#define YC_KERNEL_API_H

#include "yc_base.h"

#ifdef YC_HOST_TEST
#define YC_KFN(name) yc_testk_##name
#else
#define YC_KFN(name) name
#endif

#define YC_UL_COMPARE_AND_WAIT 1
#define YC_UL_UNFAIR_LOCK 2
#define YC_UL_COMPARE_AND_WAIT_SHARED 3
#define YC_UL_UNFAIR_LOCK64_SHARED 4
#define YC_UL_COMPARE_AND_WAIT64 5
#define YC_UL_COMPARE_AND_WAIT64_SHARED 6
#define YC_ULF_WAKE_ALL 0x00000100u
#define YC_ULF_WAKE_THREAD 0x00000200u
#define YC_ULF_WAKE_ALLOW_NON_OWNER 0x00000400u
#define YC_ULF_NO_ERRNO 0x01000000u

int YC_KFN(__ulock_wait)(yc_u32 operation, void *addr, yc_u64 value, yc_u32 timeout_us);
int YC_KFN(__ulock_wait2)(yc_u32 operation, void *addr, yc_u64 value, yc_u64 timeout_ns, yc_u64 value2);
int YC_KFN(__ulock_wake)(yc_u32 operation, void *addr, yc_u64 wake_value);

int *YC_KFN(__error)(void);
yc_ssize_t YC_KFN(write)(int fd, const void *buf, yc_size_t len);
void *YC_KFN(mmap)(void *addr, yc_size_t len, int prot, int flags, int fd, yc_i64 offset);
int YC_KFN(munmap)(void *addr, yc_size_t len);
int YC_KFN(sigprocmask)(int how, const yc_u32 *set, yc_u32 *oset);
int YC_KFN(__sigaction)(int sig, const void *nsa, void *osa);
yc_u64 YC_KFN(mach_absolute_time)(void);
struct yc_mach_timebase_info { yc_u32 numer; yc_u32 denom; };
int YC_KFN(mach_timebase_info)(struct yc_mach_timebase_info *info);

struct yc_libkernel_string_functions {
    unsigned long version;
    void *bzero, *memchr, *memcmp, *memmove, *memccpy, *memset, *strchr, *strcmp;
    void *strcpy, *strlcat, *strlcpy, *strlen, *strncmp, *strncpy, *strnlen, *strstr;
};
int YC_KFN(__libkernel_platform_init)(const struct yc_libkernel_string_functions *funcs);

struct yc_alloc_once_slot {
    long once;
    void *ptr;
};
extern struct yc_alloc_once_slot YC_KFN(_os_alloc_once_table)[100];
#define YC_OS_ALLOC_ONCE_KEY_LIBSYSTEM_PLATFORM_ASL 21

#define YC_PROT_READ 0x1
#define YC_PROT_WRITE 0x2
#define YC_MAP_PRIVATE 0x0002
#define YC_MAP_ANON 0x1000
#define YC_MAP_FAILED ((void *)-1)
#define YC_SIG_BLOCK 1
#define YC_SIG_SETMASK 3

#endif
