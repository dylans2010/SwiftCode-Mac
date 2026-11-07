#include "yc_pthread.h"

YC_EXPORT yc_pthread_t YC_FN(pthread_from_mach_thread_np)(yc_u32 port);

typedef void (*yc_dtor_t)(void *);

#define KEY_FREE 0
#define KEY_CREATED 1

static yc_dtor_t key_dtor[YC_TSD_SLOTS];
static yc_u8 key_state[YC_TSD_SLOTS];
static yc_u32 key_lock;

YC_EXPORT void *YC_FN(pthread_getspecific)(unsigned long key)
{
    return (void *)__yc_tsd()[key];
}

static void note_key_used(unsigned long key)
{
    yc_pthread_t self = __yc_self();
    if (self->max_tsd_key < key)
        self->max_tsd_key = (yc_u16)key;
}

YC_EXPORT int YC_FN(pthread_setspecific)(unsigned long key, const void *value)
{
    if (key < YC_TSD_FIRST_STATIC_KEY || key >= YC_TSD_SLOTS)
        return YC_EINVAL;
    if (key >= YC_TSD_FIRST_DYNAMIC_KEY && YC_LOAD_ACQ(&key_state[key]) != KEY_CREATED)
        return YC_EINVAL;
    __yc_tsd()[key] = (yc_uintptr_t)value;
    note_key_used(key);
    return 0;
}

YC_EXPORT int YC_FN(_pthread_setspecific_static)(unsigned long key, const void *value)
{
    if (key >= YC_TSD_FIRST_DYNAMIC_KEY)
        return YC_EINVAL;
    __yc_tsd()[key] = (yc_uintptr_t)value;
    if (key >= YC_TSD_FIRST_STATIC_KEY)
        note_key_used(key);
    return 0;
}

YC_EXPORT int YC_FN(pthread_key_init_np)(int key, yc_dtor_t dtor)
{
    if (key < YC_TSD_FIRST_STATIC_KEY || key >= YC_TSD_FIRST_DYNAMIC_KEY)
        return YC_EINVAL;
    __yc_lock(&key_lock);
    key_dtor[key] = dtor;
    YC_STORE_REL(&key_state[key], KEY_CREATED);
    __yc_unlock(&key_lock);
    return 0;
}

YC_EXPORT int YC_FN(pthread_key_create)(unsigned long *key, yc_dtor_t dtor)
{
    if (key == YC_NULL)
        return YC_EINVAL;
    int r = YC_EAGAIN;
    __yc_lock(&key_lock);
    for (unsigned long k = YC_TSD_FIRST_DYNAMIC_KEY; k < YC_TSD_SLOTS; k++) {
        if (key_state[k] == KEY_FREE) {
            key_dtor[k] = dtor;
            YC_STORE_REL(&key_state[k], KEY_CREATED);
            *key = k;
            r = 0;
            break;
        }
    }
    __yc_unlock(&key_lock);
    return r;
}

YC_EXPORT int YC_FN(pthread_key_delete)(unsigned long key)
{
    if (key < YC_TSD_FIRST_DYNAMIC_KEY || key >= YC_TSD_SLOTS)
        return YC_EINVAL;
    int r = YC_EINVAL;
    __yc_lock(&key_lock);
    if (key_state[key] == KEY_CREATED) {
        key_dtor[key] = YC_NULL;
        YC_STORE_REL(&key_state[key], KEY_FREE);
        __yc_lock(&__yc_pt.list_lock);
        yc_pthread_t m = __yc_main_thread();
        m->tsd[key] = 0;
        for (yc_pthread_t p = m->next; p; p = p->next)
            p->tsd[key] = 0;
        __yc_unlock(&__yc_pt.list_lock);
        __yc_tsd()[key] = 0;
        r = 0;
    }
    __yc_unlock(&key_lock);
    return r;
}

YC_EXPORT void YC_FN(_pthread_clear_qos_tsd)(yc_u32 thread_port)
{
    yc_uintptr_t *tsd = __yc_tsd();
    if (thread_port == 0 || (yc_u32)tsd[YC_TSD_MACH_THREAD_SELF] == thread_port) {
        tsd[YC_TSD_QOS] = 0;
        return;
    }
    yc_pthread_t t = YC_FN(pthread_from_mach_thread_np)(thread_port);
    if (t != YC_NULL)
        t->tsd[YC_TSD_QOS] = 0;
}

YC_HIDDEN void __yc_tsd_run_destructors(yc_pthread_t self)
{
    for (int round = 0; round < YC_PTHREAD_DESTRUCTOR_ITERATIONS; round++) {
        yc_bool ran = 0;
        unsigned long top = self->max_tsd_key;
        if (top >= YC_TSD_SLOTS)
            top = YC_TSD_SLOTS - 1;
        for (unsigned long k = YC_TSD_FIRST_STATIC_KEY; k <= top; k++) {
            void *v = (void *)self->tsd[k];
            if (v == YC_NULL || YC_LOAD_ACQ(&key_state[k]) != KEY_CREATED)
                continue;
            yc_dtor_t d = key_dtor[k];
            if (d == YC_NULL)
                continue;
            self->tsd[k] = 0;
            d(v);
            ran = 1;
        }
        if (!ran)
            break;
    }
}
