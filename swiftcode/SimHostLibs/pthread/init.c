#include "yc_pthread.h"

YC_HIDDEN struct yc_pthread_globals __yc_pt = {
    .user_priority = 31,
    .min_priority = 0,
    .max_priority = 79,
    .main_qos = YC_PP_DEFAULT,
    .concurrency = 0,
};

YC_HIDDEN yc_size_t __yc_strlen(const char *s)
{
    yc_size_t n = 0;
    while (s[n])
        n++;
    return n;
}

YC_HIDDEN const char *__yc_getenv(const char **vec, const char *key)
{
    if (vec == YC_NULL || key == YC_NULL)
        return YC_NULL;
    for (; *vec; vec++) {
        const char *s = *vec, *k = key;
        while (*k && *s == *k) {
            s++;
            k++;
        }
        if (*k == 0 && *s == '=')
            return s + 1;
    }
    return YC_NULL;
}

static const char *parse_hex(const char *s, yc_u64 *out)
{
    if (s == YC_NULL || s[0] != '0' || (s[1] != 'x' && s[1] != 'X'))
        return YC_NULL;
    const char *p = s + 2;
    yc_u64 v = 0;
    int digits = 0;
    for (; *p && *p != ','; p++, digits++) {
        int d;
        if (*p >= '0' && *p <= '9') d = *p - '0';
        else if (*p >= 'a' && *p <= 'f') d = *p - 'a' + 10;
        else if (*p >= 'A' && *p <= 'F') d = *p - 'A' + 10;
        else return YC_NULL;
        v = (v << 4) | (yc_u64)d;
    }
    if (digits == 0)
        return YC_NULL;
    *out = v;
    return p;
}

static void erase_value(const char *value)
{
    char *p = (char *)value;
    while (*p)
        *p++ = 0;
}

YC_HIDDEN YC_NORETURN void __yc_fatal(const char *msg)
{
    static const char prefix[] = "libsystem_pthread: ";
    YC_KFN(write)(2, prefix, sizeof prefix - 1);
    YC_KFN(write)(2, msg, __yc_strlen(msg));
    YC_KFN(write)(2, "\n", 1);
    YC_CRASH();
}

#ifndef YC_HOST_TEST
static struct yc_pthread fallback_main __attribute__((aligned(64)));

YC_HIDDEN yc_uintptr_t *__yc_fallback_tsd(void)
{
    struct yc_pthread *t = &fallback_main;
    if (t->tsd[YC_TSD_SELF] == 0) {
        t->tsd[YC_TSD_ERRNO] = (yc_uintptr_t)&t->err_no;
        t->tsd[YC_TSD_SELF] = (yc_uintptr_t)t;
    }
    return t->tsd;
}
#endif

YC_HIDDEN void __yc_thread_defaults(yc_pthread_t t)
{
    if (YC_LIKELY(YC_LOAD_ACQ(&t->flags) & YC_TF_DEFAULTS_SET))
        return;
    if (t->tsd[YC_TSD_SELF] == 0)
        t->tsd[YC_TSD_SELF] = (yc_uintptr_t)t;
    if (t->tsd[YC_TSD_ERRNO] == 0)
        t->tsd[YC_TSD_ERRNO] = (yc_uintptr_t)&t->err_no;
    if (t->tsd[YC_TSD_QOS] == 0)
        t->tsd[YC_TSD_QOS] = __yc_pt.main_qos;
    if (t->tsd[YC_TSD_PTR_MUNGE] == 0)
        t->tsd[YC_TSD_PTR_MUNGE] = __yc_pt.munge_token;
    if (t->thread_id == 0) {
        yc_u64 id = YC_KFN(__thread_selfid)();
        t->thread_id = (id == 0 || id == ~0ull) ? 1 : id;
    }
    t->sig = (long)((yc_uintptr_t)t ^ __yc_pt.munge_token);
    t->policy = YC_SCHED_OTHER;
    t->sched_priority = __yc_pt.user_priority;
    t->detach_flags = 1;
    t->cancel_state = YC_PTHREAD_CANCEL_ENABLE | YC_PTHREAD_CANCEL_DEFERRED;
    if (t->guardsize == 0)
        t->guardsize = YC_PAGE_SIZE;
    if (t->exit_gate == 0)
        t->exit_gate = (yc_u32)t->tsd[YC_TSD_MACH_THREAD_SELF];
    if (t->stackaddr == 0) {
        yc_uintptr_t sp = (yc_uintptr_t)__builtin_frame_address(0);
        t->stackaddr = (sp + YC_PAGE_SIZE - 1) & ~(YC_PAGE_SIZE - 1);
        t->stackbottom = t->stackaddr - 8 * 1024 * 1024;
    }
    __atomic_fetch_or(&t->flags, YC_TF_DEFAULTS_SET, __ATOMIC_RELEASE);
}

YC_HIDDEN yc_pthread_t __yc_main_thread(void)
{
    yc_pthread_t m = YC_LOAD_ACQ(&__yc_pt.main_thread);
    if (YC_LIKELY(m != YC_NULL))
        return m;
    yc_pthread_t self = __yc_self();
    yc_pthread_t expected = YC_NULL;
    if (__atomic_compare_exchange_n(&__yc_pt.main_thread, &expected, self, 0, __ATOMIC_ACQ_REL,
                                    __ATOMIC_ACQUIRE)) {
        __atomic_fetch_or(&self->flags, YC_TF_MAIN, __ATOMIC_RELAXED);
        if (__yc_pt.thread_count == 0)
            __yc_pt.thread_count = 1;
        self->next = self->prev = YC_NULL;
        return self;
    }
    return expected;
}

YC_HIDDEN yc_pthread_t __yc_self_ready(void)
{
    yc_pthread_t self = __yc_self();
    __yc_main_thread();
    __yc_thread_defaults(self);
    return self;
}

YC_HIDDEN yc_bool __yc_thread_valid(yc_pthread_t t)
{
    if (t == YC_NULL)
        return 0;
    if (t == __yc_self() || t == __yc_main_thread())
        return 1;
    yc_bool found = 0;
    __yc_lock(&__yc_pt.list_lock);
    for (yc_pthread_t p = __yc_main_thread()->next; p; p = p->next)
        if (p == t) {
            found = 1;
            break;
        }
    __yc_unlock(&__yc_pt.list_lock);
    return found;
}

struct __attribute__((packed)) yc_bsdthread_record {
    yc_u64 version;
    yc_u64 dispatch_queue_offset;
    yc_u64 main_qos;
    yc_u32 tsd_offset;
    yc_u32 return_to_kernel_offset;
    yc_u32 mach_thread_self_offset;
    yc_u64 stack_addr_hint;
    yc_u32 mutex_default_policy;
    yc_u32 joinable_offset_bits;
    yc_u32 wq_quantum_expiry_offset;
};
_Static_assert(sizeof(struct yc_bsdthread_record) == 56, "registration record is 56 bytes");
_Static_assert(__builtin_offsetof(struct yc_bsdthread_record, stack_addr_hint) == 36, "hint at 36");
_Static_assert(__builtin_offsetof(struct yc_bsdthread_record, wq_quantum_expiry_offset) == 52, "quantum at 52");

#define YC_FEATURES_REQUIRED 0x4000001Eull

static void register_with_kernel(yc_pthread_t mt)
{
    if (__yc_pt.registered)
        return;
    __yc_pt.registered = 1;
    struct yc_bsdthread_record rec;
    __builtin_memset(&rec, 0, sizeof rec);
    rec.version = sizeof rec;
    rec.dispatch_queue_offset = YC_TSD_DISPATCH_QUEUE * 8;
    rec.tsd_offset = YC_PTHREAD_TSD_OFFSET;
    rec.return_to_kernel_offset = YC_TSD_RETURN_TO_KERNEL * 8;
    rec.mach_thread_self_offset = YC_TSD_MACH_THREAD_SELF * 8;
    rec.joinable_offset_bits = 8 * __builtin_offsetof(struct yc_pthread, detach_flags);
    rec.wq_quantum_expiry_offset = YC_TSD_WQ_QUANTUM * 8;
    int r = YC_KFN(__bsdthread_register)((void *)YC_KFN(thread_start), (void *)YC_KFN(start_wqthread),
                                         YC_PTHREAD_SIZE, &rec, (int)sizeof rec,
                                         YC_TSD_DISPATCH_QUEUE * 8);
    if (r <= 0) {
        __yc_pt.features = 0;
        return;
    }
    __yc_pt.features = r;
    if (rec.main_qos != 0) {
        __yc_pt.main_qos = rec.main_qos;
        mt->tsd[YC_TSD_QOS] = rec.main_qos;
    }
    if (rec.stack_addr_hint != 0)
        __yc_pt.stack_addr_hint = rec.stack_addr_hint;
    __yc_pt.mutex_default_policy = rec.mutex_default_policy;
}

struct yc_libpthread_functions {
    unsigned long version;
    void (*exit)(int);
    void *(*malloc)(yc_size_t);
    void (*free)(void *);
};
_Static_assert(sizeof(struct yc_libpthread_functions) == 32, "_libpthread_functions v2 is 32 bytes");

YC_EXPORT int YC_FN(__pthread_init)(const struct yc_libpthread_functions *funcs, const char **envp,
                                    const char **apple, const void *vars)
{
    (void)vars;
    if (funcs != YC_NULL && funcs->version >= 1) {
        if (funcs->exit)
            __yc_pt.exit_fn = funcs->exit;
        if (funcs->version >= 2) {
            if (funcs->malloc)
                __yc_pt.malloc_fn = funcs->malloc;
            if (funcs->free)
                __yc_pt.free_fn = funcs->free;
        }
    }

    yc_uintptr_t *tsd = __yc_tsd();
#ifndef YC_HOST_TEST
    yc_uintptr_t reg;
    __asm__ volatile("mrs %0, tpidrro_el0" : "=r"(reg));
    if (reg == 0)
        YC_KFN(_thread_set_tsd_base)(tsd);
#endif
    yc_pthread_t mt = __yc_from_tsd(tsd);
    yc_pthread_t expected = YC_NULL;
    if (!__atomic_compare_exchange_n(&__yc_pt.main_thread, &expected, mt, 0, __ATOMIC_ACQ_REL,
                                     __ATOMIC_ACQUIRE) && expected != mt)
        return 0;
    __atomic_fetch_or(&mt->flags, YC_TF_MAIN, __ATOMIC_RELAXED);

    const char *ms = __yc_getenv(apple, "main_stack");
    if (ms) {
        yc_u64 v[4] = { 0, 0, 0, 0 };
        const char *p = ms;
        int n = 0;
        while (n < 4 && p && (p = parse_hex(p, &v[n])) != YC_NULL) {
            n++;
            if (*p != ',')
                break;
            p++;
        }
        if (n >= 2 && v[0] != 0 && v[1] != 0) {
            mt->stackaddr = v[0];
            mt->stackbottom = v[0] - v[1];
            mt->freeaddr = n >= 3 ? v[2] : 0;
            mt->freesize = n >= 4 ? v[3] : 0;
        }
        erase_value(ms);
    }
    mt->guardsize = YC_PAGE_SIZE;

    yc_u64 token = 0;
    const char *pm = __yc_getenv(apple, "ptr_munge");
    if (pm) {
        parse_hex(pm, &token);
        erase_value(pm);
    }
    if (token == 0)
        parse_hex(__yc_getenv(envp, "PTHREAD_PTR_MUNGE_TOKEN"), &token);
    if (token == 0)
        token = mt->tsd[YC_TSD_PTR_MUNGE];
    if (token != 0)
        __yc_pt.munge_token = token;

    mt->tsd[YC_TSD_SELF] = (yc_uintptr_t)mt;
    mt->tsd[YC_TSD_ERRNO] = (yc_uintptr_t)&mt->err_no;
    mt->tsd[YC_TSD_PTR_MUNGE] = __yc_pt.munge_token;
    if (!__yc_pt.init_done)
        mt->tsd[YC_TSD_QOS] = __yc_pt.main_qos;
    __yc_thread_defaults(mt);
    mt->sig = (long)((yc_uintptr_t)mt ^ __yc_pt.munge_token);

    yc_u64 port = 0;
    const char *tp = __yc_getenv(apple, "th_port");
    if (tp) {
        parse_hex(tp, &port);
        erase_value(tp);
    }

    if (!__yc_pt.init_done) {
        __yc_lock(&__yc_pt.list_lock);
        mt->next = mt->prev = YC_NULL;
        __yc_pt.thread_count = 1;
        __yc_unlock(&__yc_pt.list_lock);
    }
    if (port != 0)
        mt->tsd[YC_TSD_MACH_THREAD_SELF] = (yc_u32)port;
    else if (mt->tsd[YC_TSD_MACH_THREAD_SELF] == 0)
        mt->tsd[YC_TSD_MACH_THREAD_SELF] = YC_KFN(mach_thread_self)();
    mt->exit_gate = (yc_u32)mt->tsd[YC_TSD_MACH_THREAD_SELF];
    if (mt->tsd[YC_TSD_MIG_REPLY] == 0)
        mt->tsd[YC_TSD_MIG_REPLY] = YC_KFN(mach_reply_port)();
    if (!__yc_pt.init_done) {
        mt->tsd[YC_TSD_MACH_SPECIAL_REPLY] = 0;
        mt->tsd[YC_TSD_SEMAPHORE_CACHE] = 0;
    }

    register_with_kernel(mt);

    const char *y = __yc_getenv(envp, "PTHREAD_YIELD_TO_ZERO");
    __yc_pt.yield_to_zero = (y != YC_NULL && y[0] == '1');

    __yc_pt.init_done = 1;
    return 0;
}

YC_EXPORT void YC_FN(__pthread_late_init)(const char **envp, const char **apple, const void *vars)
{
    (void)envp;
    (void)apple;
    (void)vars;
    __yc_pt.late_init_done = 1;
}

YC_EXPORT void YC_FN(_pthread_set_self)(void *p)
{
    (void)p;
}

#define YC_ATFORK_MAX 170
struct yc_atfork_entry {
    void (*prepare)(void);
    void (*parent)(void);
    void (*child)(void);
};
static struct yc_atfork_entry atfork_table[YC_ATFORK_MAX];
static yc_u32 atfork_count;
static yc_u32 atfork_lock;

YC_EXPORT int YC_FN(pthread_atfork)(void (*prepare)(void), void (*parent)(void), void (*child)(void))
{
    __yc_lock(&atfork_lock);
    if (atfork_count >= YC_ATFORK_MAX) {
        __yc_unlock(&atfork_lock);
        return YC_ENOMEM;
    }
    atfork_table[atfork_count].prepare = prepare;
    atfork_table[atfork_count].parent = parent;
    atfork_table[atfork_count].child = child;
    YC_STORE_REL(&atfork_count, atfork_count + 1);
    __yc_unlock(&atfork_lock);
    return 0;
}

YC_EXPORT void YC_FN(_pthread_atfork_prepare_handlers)(void)
{
    for (yc_u32 i = YC_LOAD_ACQ(&atfork_count); i-- > 0;)
        if (atfork_table[i].prepare)
            atfork_table[i].prepare();
}

YC_EXPORT void YC_FN(_pthread_atfork_parent_handlers)(void)
{
    for (yc_u32 i = 0; i < atfork_count; i++)
        if (atfork_table[i].parent)
            atfork_table[i].parent();
}

YC_EXPORT void YC_FN(_pthread_atfork_child_handlers)(void)
{
    for (yc_u32 i = 0; i < atfork_count; i++)
        if (atfork_table[i].child)
            atfork_table[i].child();
}

YC_EXPORT void YC_FN(_pthread_atfork_prepare)(void)
{
    __yc_lock(&__yc_pt.list_lock);
}

YC_EXPORT void YC_FN(_pthread_atfork_parent)(void)
{
    __yc_unlock(&__yc_pt.list_lock);
}

YC_EXPORT void YC_FN(_pthread_atfork_child)(void)
{
    yc_pthread_t self = __yc_self();
    __yc_pt.list_lock = 0;
    __yc_pt.main_thread = self;
    __yc_pt.thread_count = 1;
    self->next = self->prev = YC_NULL;
    self->flags = (yc_u16)((self->flags & ~(YC_TF_ON_LIST | YC_TF_WORKQ | YC_TF_DETACHED)) | YC_TF_MAIN);
    self->detach_flags |= YC_DF_JOINABLE;
    YC_STORE(&YC_FN(__is_threaded), 0);
}

YC_EXPORT void YC_FN(_pthread_fork_prepare)(void)
{
    YC_FN(_pthread_atfork_prepare)();
}

YC_EXPORT void YC_FN(_pthread_fork_parent)(void)
{
    YC_FN(_pthread_atfork_parent)();
}

YC_EXPORT void YC_FN(_pthread_fork_child)(void)
{
    YC_FN(_pthread_atfork_child)();
}

YC_EXPORT void YC_FN(_pthread_fork_child_postinit)(void)
{
    yc_pthread_t self = __yc_self();
    yc_u32 port = YC_KFN(mach_thread_self)();
    if (port != 0) {
        self->tsd[YC_TSD_MACH_THREAD_SELF] = port;
        self->exit_gate = port;
    }
    self->tsd[YC_TSD_MIG_REPLY] = 0;
    yc_u64 id = YC_KFN(__thread_selfid)();
    if (id != 0 && id != ~0ull)
        self->thread_id = id;
}
