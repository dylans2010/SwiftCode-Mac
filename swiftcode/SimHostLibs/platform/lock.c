#include "yc_platform.h"

#define LOAD(p) __atomic_load_n((p), __ATOMIC_RELAXED)
#define CAS_ACQ(p, expp, des) \
    __atomic_compare_exchange_n((p), (expp), (des), 0, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED)
#define CAS_RLX(p, expp, des) \
    __atomic_compare_exchange_n((p), (expp), (des), 0, __ATOMIC_RELAXED, __ATOMIC_RELAXED)

static YC_NOINLINE YC_NORETURN void unfair_lock_corrupt(yc_u32 *word)
{
#if defined(__aarch64__) && !defined(YC_HOST_TEST)
    void **fp = __builtin_frame_address(0);
    void **slow = fp ? (void **)fp[0] : YC_NULL;
    void *ra = slow ? slow[1] : YC_NULL;
    register const char *x0 __asm__("x0") = "os_unfair_lock: corrupt lock (the owner is not a thread)";
    register yc_u32 *x1 __asm__("x1") = word;
    __asm__ volatile("mov x30, %2\n\tbrk #0x7964" : : "r"(x0), "r"(x1), "r"(ra) : "x30", "memory");
    __builtin_unreachable();
#else
    (void)word;
    YC_CRASH();
#endif
}

static YC_NOINLINE void unfair_lock_slow(yc_u32 *word, yc_u32 self)
{
    yc_bool waited = 0;
    for (;;) {
        yc_u32 cur = LOAD(word);
        if (cur == 0) {
            yc_u32 want = waited ? (self & ~1u) : self;
            if (CAS_ACQ(word, &cur, want))
                return;
            continue;
        }
        if ((cur | 1u) == self)
            YC_CRASH();
        if (cur & 1u) {
            if (!CAS_RLX(word, &cur, cur & ~1u))
                continue;
            cur &= ~1u;
        }
        int r = YC_KFN(__ulock_wait2)(YC_UL_UNFAIR_LOCK | YC_ULF_NO_ERRNO, word, cur, 0, 0);
        if (r == -YC_EOWNERDEAD)
            unfair_lock_corrupt(word);
        waited = 1;
    }
}

YC_HIDDEN void __yc_unfair_lock(yc_u32 *word, yc_u32 self)
{
    yc_u32 expected = 0;
    if (YC_LIKELY(CAS_ACQ(word, &expected, self)))
        return;
    unfair_lock_slow(word, self);
}

YC_HIDDEN yc_bool __yc_unfair_trylock(yc_u32 *word, yc_u32 self)
{
    yc_u32 expected = 0;
    return CAS_ACQ(word, &expected, self);
}

YC_HIDDEN void __yc_unfair_unlock(yc_u32 *word, yc_u32 self)
{
    yc_u32 old = __atomic_exchange_n(word, 0, __ATOMIC_RELEASE);
    if (YC_LIKELY(old == self))
        return;
    if ((old | 1u) != self)
        YC_CRASH();
    YC_KFN(__ulock_wake)(YC_UL_UNFAIR_LOCK | YC_ULF_NO_ERRNO, word, 0);
}

#define SPIN_TRIES 100

YC_HIDDEN yc_bool __yc_futex_trylock(yc_i32 *word)
{
    yc_i32 expected = 0;
    return CAS_ACQ(word, &expected, 1);
}

YC_HIDDEN void __yc_futex_lock(yc_i32 *word)
{
    yc_i32 expected = 0;
    if (YC_LIKELY(CAS_ACQ(word, &expected, 1)))
        return;
    for (int i = 0; i < SPIN_TRIES; i++) {
        YC_CPU_RELAX();
        expected = 0;
        if (LOAD(word) == 0 && CAS_ACQ(word, &expected, 1))
            return;
    }
    while (__atomic_exchange_n(word, 2, __ATOMIC_ACQUIRE) != 0)
        YC_KFN(__ulock_wait)(YC_UL_COMPARE_AND_WAIT | YC_ULF_NO_ERRNO, word, 2, 0);
}

YC_HIDDEN void __yc_futex_unlock(yc_i32 *word)
{
    if (__atomic_exchange_n(word, 0, __ATOMIC_RELEASE) == 2)
        YC_KFN(__ulock_wake)(YC_UL_COMPARE_AND_WAIT | YC_ULF_NO_ERRNO, word, 0);
}

typedef struct { yc_u32 opaque; } yc_unfair_lock;

YC_EXPORT void YC_FN(os_unfair_lock_lock)(yc_unfair_lock *lock)
{
    __yc_unfair_lock(&lock->opaque, __yc_lock_owner_id());
}

YC_EXPORT void YC_FN(os_unfair_lock_lock_with_options)(yc_unfair_lock *lock, yc_u32 options)
{
    (void)options;
    __yc_unfair_lock(&lock->opaque, __yc_lock_owner_id());
}

YC_EXPORT void YC_FN(os_unfair_lock_lock_with_flags)(yc_unfair_lock *lock, yc_u32 flags)
{
    (void)flags;
    __yc_unfair_lock(&lock->opaque, __yc_lock_owner_id());
}

YC_EXPORT yc_bool YC_FN(os_unfair_lock_trylock)(yc_unfair_lock *lock)
{
    return __yc_unfair_trylock(&lock->opaque, __yc_lock_owner_id());
}

YC_EXPORT void YC_FN(os_unfair_lock_unlock)(yc_unfair_lock *lock)
{
    __yc_unfair_unlock(&lock->opaque, __yc_lock_owner_id());
}

YC_EXPORT void YC_FN(os_unfair_lock_lock_no_tsd)(yc_unfair_lock *lock, yc_u32 options, yc_u32 thread_port)
{
    (void)options;
    __yc_unfair_lock(&lock->opaque, thread_port | 1u);
}

YC_EXPORT void YC_FN(os_unfair_lock_unlock_no_tsd)(yc_unfair_lock *lock, yc_u32 thread_port)
{
    __yc_unfair_unlock(&lock->opaque, thread_port | 1u);
}

YC_EXPORT void YC_FN(os_unfair_lock_assert_owner)(const yc_unfair_lock *lock)
{
    yc_u32 cur = LOAD(&lock->opaque);
    if (cur == 0 || (cur | 1u) != __yc_lock_owner_id())
        YC_CRASH();
}

YC_EXPORT void YC_FN(os_unfair_lock_assert_not_owner)(const yc_unfair_lock *lock)
{
    yc_u32 cur = LOAD(&lock->opaque);
    if (cur != 0 && (cur | 1u) == __yc_lock_owner_id())
        YC_CRASH();
}

typedef struct { yc_u32 lock; yc_u32 count; } yc_recursive_lock;

static yc_bool recursive_owned(yc_recursive_lock *l, yc_u32 self)
{
    yc_u32 cur = LOAD(&l->lock);
    return cur != 0 && (cur | 1u) == self;
}

YC_EXPORT void YC_FN(os_unfair_recursive_lock_lock_with_options)(yc_recursive_lock *l, yc_u32 options)
{
    (void)options;
    yc_u32 self = __yc_lock_owner_id();
    if (recursive_owned(l, self)) {
        l->count++;
        return;
    }
    __yc_unfair_lock(&l->lock, self);
}

YC_EXPORT yc_bool YC_FN(os_unfair_recursive_lock_trylock)(yc_recursive_lock *l)
{
    yc_u32 self = __yc_lock_owner_id();
    if (recursive_owned(l, self)) {
        l->count++;
        return 1;
    }
    return __yc_unfair_trylock(&l->lock, self);
}

YC_EXPORT void YC_FN(os_unfair_recursive_lock_unlock)(yc_recursive_lock *l)
{
    yc_u32 self = __yc_lock_owner_id();
    if (!recursive_owned(l, self))
        YC_CRASH();
    if (l->count) {
        l->count--;
        return;
    }
    __yc_unfair_unlock(&l->lock, self);
}

YC_EXPORT yc_bool YC_FN(os_unfair_recursive_lock_tryunlock4objc)(yc_recursive_lock *l)
{
    yc_u32 self = __yc_lock_owner_id();
    if (!recursive_owned(l, self))
        return 0;
    if (l->count)
        l->count--;
    else
        __yc_unfair_unlock(&l->lock, self);
    return 1;
}

YC_EXPORT yc_bool YC_FN(os_unfair_recursive_lock_owned)(yc_recursive_lock *l)
{
    return recursive_owned(l, __yc_lock_owner_id());
}

YC_EXPORT void YC_FN(os_unfair_recursive_lock_unlock_forked_child)(yc_recursive_lock *l)
{
    if (LOAD(&l->lock) == 0)
        YC_CRASH();
    if (l->count)
        l->count--;
    else
        __atomic_store_n(&l->lock, 0, __ATOMIC_RELEASE);
}

YC_EXPORT void YC_FN(_os_nospin_lock_lock)(yc_i32 *lock) { __yc_futex_lock(lock); }
YC_EXPORT yc_bool YC_FN(_os_nospin_lock_trylock)(yc_i32 *lock) { return __yc_futex_trylock(lock); }
YC_EXPORT void YC_FN(_os_nospin_lock_unlock)(yc_i32 *lock) { __yc_futex_unlock(lock); }

YC_EXPORT void YC_FN(OSSpinLockLock)(volatile yc_i32 *lock) { __yc_futex_lock((yc_i32 *)lock); }
YC_EXPORT yc_bool YC_FN(OSSpinLockTry)(volatile yc_i32 *lock) { return __yc_futex_trylock((yc_i32 *)lock); }
YC_EXPORT void YC_FN(OSSpinLockUnlock)(volatile yc_i32 *lock) { __yc_futex_unlock((yc_i32 *)lock); }
YC_EXPORT void YC_FN(_OSSpinLockLockSlow)(volatile yc_i32 *lock) { __yc_futex_lock((yc_i32 *)lock); }

YC_EXPORT void YC_FN(spin_lock)(volatile yc_i32 *lock) { __yc_futex_lock((yc_i32 *)lock); }
YC_EXPORT yc_bool YC_FN(spin_lock_try)(volatile yc_i32 *lock) { return __yc_futex_trylock((yc_i32 *)lock); }
YC_EXPORT void YC_FN(spin_unlock)(volatile yc_i32 *lock) { __yc_futex_unlock((yc_i32 *)lock); }
YC_EXPORT void YC_FN(_spin_lock)(volatile yc_i32 *lock) { __yc_futex_lock((yc_i32 *)lock); }
YC_EXPORT yc_bool YC_FN(_spin_lock_try)(volatile yc_i32 *lock) { return __yc_futex_trylock((yc_i32 *)lock); }
YC_EXPORT void YC_FN(_spin_unlock)(volatile yc_i32 *lock) { __yc_futex_unlock((yc_i32 *)lock); }

struct yc_os_lock_type {
    yc_uintptr_t kind;
    void (*lock)(void *);
    yc_bool (*trylock)(void *);
    void (*unlock)(void *);
};
struct yc_os_lock_object {
    const struct yc_os_lock_type *type;
    yc_u32 word;
};

static void futex_obj_lock(void *o) { __yc_futex_lock((yc_i32 *)&((struct yc_os_lock_object *)o)->word); }
static yc_bool futex_obj_trylock(void *o) { return __yc_futex_trylock((yc_i32 *)&((struct yc_os_lock_object *)o)->word); }
static void futex_obj_unlock(void *o) { __yc_futex_unlock((yc_i32 *)&((struct yc_os_lock_object *)o)->word); }
static void unfair_obj_lock(void *o) { __yc_unfair_lock(&((struct yc_os_lock_object *)o)->word, __yc_lock_owner_id()); }
static yc_bool unfair_obj_trylock(void *o) { return __yc_unfair_trylock(&((struct yc_os_lock_object *)o)->word, __yc_lock_owner_id()); }
static void unfair_obj_unlock(void *o) { __yc_unfair_unlock(&((struct yc_os_lock_object *)o)->word, __yc_lock_owner_id()); }

YC_EXPORT const struct yc_os_lock_type YC_FN(_os_lock_type_spin) = { 1, futex_obj_lock, futex_obj_trylock, futex_obj_unlock };
YC_EXPORT const struct yc_os_lock_type YC_FN(_os_lock_type_eliding) = { 1, futex_obj_lock, futex_obj_trylock, futex_obj_unlock };
YC_EXPORT const struct yc_os_lock_type YC_FN(_os_lock_type_transactional) = { 1, futex_obj_lock, futex_obj_trylock, futex_obj_unlock };
YC_EXPORT const struct yc_os_lock_type YC_FN(_os_lock_type_nospin) = { 2, futex_obj_lock, futex_obj_trylock, futex_obj_unlock };
YC_EXPORT const struct yc_os_lock_type YC_FN(_os_lock_type_handoff) = { 3, unfair_obj_lock, unfair_obj_trylock, unfair_obj_unlock };
YC_EXPORT const struct yc_os_lock_type YC_FN(_os_lock_type_unfair) = { 4, unfair_obj_lock, unfair_obj_trylock, unfair_obj_unlock };

YC_EXPORT void YC_FN(os_lock_lock)(void *lock)
{
    ((struct yc_os_lock_object *)lock)->type->lock(lock);
}

YC_EXPORT yc_bool YC_FN(os_lock_trylock)(void *lock)
{
    return ((struct yc_os_lock_object *)lock)->type->trylock(lock);
}

YC_EXPORT void YC_FN(os_lock_unlock)(void *lock)
{
    ((struct yc_os_lock_object *)lock)->type->unlock(lock);
}
