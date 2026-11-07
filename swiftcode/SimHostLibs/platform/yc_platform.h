#ifndef YC_PLATFORM_H
#define YC_PLATFORM_H

#include "yc_base.h"
#include "yc_kernel_api.h"

YC_HIDDEN yc_u32 __yc_lock_owner_id(void);
#define YC_TSD_SLOT_MACH_THREAD_SELF 3
#define YC_FALLBACK_OWNER_ID 0x203u

YC_HIDDEN void __yc_unfair_lock(yc_u32 *word, yc_u32 self);
YC_HIDDEN yc_bool __yc_unfair_trylock(yc_u32 *word, yc_u32 self);
YC_HIDDEN void __yc_unfair_unlock(yc_u32 *word, yc_u32 self);
YC_HIDDEN void __yc_futex_lock(yc_i32 *word);
YC_HIDDEN yc_bool __yc_futex_trylock(yc_i32 *word);
YC_HIDDEN void __yc_futex_unlock(yc_i32 *word);

#if defined(__aarch64__)
#define YC_CPU_RELAX() __asm__ volatile("yield" ::: "memory")
#elif defined(__x86_64__)
#define YC_CPU_RELAX() __asm__ volatile("pause" ::: "memory")
#else
#define YC_CPU_RELAX() do { } while (0)
#endif

YC_HIDDEN yc_size_t __yc_strlen(const char *s);

#endif
