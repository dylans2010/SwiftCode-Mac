#include "yc_pthread.h"

static const unsigned qos_classes[7] = {
    YC_QOS_CLASS_UNSPECIFIED, YC_QOS_CLASS_MAINTENANCE, YC_QOS_CLASS_BACKGROUND, YC_QOS_CLASS_UTILITY,
    YC_QOS_CLASS_DEFAULT,     YC_QOS_CLASS_USER_INITIATED, YC_QOS_CLASS_USER_INTERACTIVE,
};

YC_HIDDEN int __yc_qos_index(unsigned qos_class)
{
    for (int i = 0; i < 7; i++)
        if (qos_classes[i] == qos_class)
            return i;
    return -1;
}

YC_HIDDEN unsigned __yc_qos_class(int index)
{
    return (index >= 0 && index < 7) ? qos_classes[index] : YC_QOS_CLASS_UNSPECIFIED;
}

YC_HIDDEN yc_u64 __yc_pp_make(int index, int relpri, yc_u64 flags)
{
    yc_u64 pp = flags & YC_PP_FLAGS_MASK;
    if (index > 0 && index < 7)
        pp |= (1ull << (8 + index - 1)) | (yc_u8)(relpri - 1);
    return pp;
}

YC_HIDDEN unsigned __yc_pp_decode(yc_u64 pp, int *relpri, yc_u64 *flags)
{
    if (flags)
        *flags = pp & YC_PP_FLAGS_MASK;
    yc_u64 bits = (pp >> 8) & 0x3F;
    int index = 0;
    for (int i = 6; i >= 1; i--)
        if (bits & (1ull << (i - 1))) {
            index = i;
            break;
        }
    if (relpri)
        *relpri = index ? (int)(signed char)(yc_u8)((pp & 0xFF) + 1) : 0;
    return __yc_qos_class(index);
}

YC_EXPORT unsigned YC_FN(qos_class_self)(void)
{
    yc_u64 pp = __yc_tsd()[YC_TSD_QOS];
    if (pp == 0 && !__yc_pt.init_done)
        pp = __yc_pt.main_qos;
    return __yc_pp_decode(pp, YC_NULL, YC_NULL);
}

YC_EXPORT unsigned YC_FN(qos_class_main)(void)
{
    return __yc_pp_decode(__yc_pt.main_qos, YC_NULL, YC_NULL);
}

static int set_qos(yc_pthread_t t, unsigned qos, int relpri)
{
    int idx = __yc_qos_index(qos);
    if (idx < 0 || relpri > 0 || relpri < YC_QOS_MIN_RELATIVE_PRIORITY)
        return YC_EINVAL;
    t->tsd[YC_TSD_QOS] = __yc_pp_make(idx, relpri, 0);
    return 0;
}

YC_EXPORT int YC_FN(pthread_set_qos_class_self_np)(unsigned qos, int relpri)
{
    return set_qos(__yc_self(), qos, relpri);
}

YC_EXPORT int YC_FN(pthread_set_qos_class_np)(yc_pthread_t t, unsigned qos, int relpri)
{
    if (t != __yc_self())
        return YC_EPERM;
    return set_qos(t, qos, relpri);
}

YC_EXPORT int YC_FN(pthread_get_qos_class_np)(yc_pthread_t t, unsigned *qos, int *relpri)
{
    if (!__yc_thread_valid(t))
        return YC_ESRCH;
    int rp = 0;
    unsigned q = __yc_pp_decode(t->tsd[YC_TSD_QOS], &rp, YC_NULL);
    if (qos)
        *qos = q;
    if (relpri)
        *relpri = rp;
    return 0;
}

static yc_u64 override_token;

YC_EXPORT void *YC_FN(pthread_override_qos_class_start_np)(yc_pthread_t t, unsigned qos, int relpri)
{
    if (!__yc_thread_valid(t) || __yc_qos_index(qos) < 0 || relpri > 0)
        return YC_NULL;
    return &override_token;
}

YC_EXPORT int YC_FN(pthread_override_qos_class_end_np)(void *override)
{
    return override == &override_token ? 0 : YC_EINVAL;
}

YC_EXPORT int YC_FN(_pthread_override_qos_class_start_direct)(yc_u32 port, yc_u64 pp)
{
    (void)port;
    (void)pp;
    return 0;
}

YC_EXPORT int YC_FN(_pthread_override_qos_class_end_direct)(yc_u32 port)
{
    (void)port;
    return 0;
}

YC_EXPORT int YC_FN(_pthread_qos_override_start_direct)(yc_u32 port, yc_u64 pp, void *resource)
{
    (void)port;
    (void)pp;
    (void)resource;
    return 0;
}

YC_EXPORT int YC_FN(_pthread_qos_override_end_direct)(yc_u32 port, void *resource)
{
    (void)port;
    (void)resource;
    return 0;
}

YC_EXPORT int YC_FN(_pthread_workqueue_override_start_direct)(yc_u32 port, yc_u64 pp)
{
    (void)port;
    (void)pp;
    return 0;
}

YC_EXPORT int YC_FN(_pthread_workqueue_override_start_direct_check_owner)(yc_u32 port, yc_u64 pp, void *ulock)
{
    (void)port;
    (void)pp;
    (void)ulock;
    return 0;
}

YC_EXPORT int YC_FN(_pthread_workqueue_override_reset)(void)
{
    return 0;
}

YC_EXPORT int YC_FN(_pthread_workqueue_asynchronous_override_add)(yc_u32 port, yc_u64 pp, void *resource)
{
    (void)port;
    (void)pp;
    (void)resource;
    return 0;
}

YC_EXPORT int YC_FN(_pthread_workqueue_asynchronous_override_reset_self)(void *resource)
{
    (void)resource;
    return 0;
}

YC_EXPORT int YC_FN(_pthread_workqueue_asynchronous_override_reset_all_self)(void)
{
    return 0;
}

YC_EXPORT yc_u64 YC_FN(_pthread_qos_class_encode)(unsigned qos, int relpri, unsigned long flags)
{
    int idx = __yc_qos_index(qos);
    if (idx < 0)
        return 0;
    return __yc_pp_make(idx, relpri, flags);
}

YC_EXPORT unsigned YC_FN(_pthread_qos_class_decode)(yc_u64 pp, int *relpri, unsigned long *flags)
{
    yc_u64 f = 0;
    unsigned q = __yc_pp_decode(pp, relpri, &f);
    if (flags)
        *flags = (unsigned long)f;
    return q;
}

YC_EXPORT int YC_FN(_pthread_set_properties_self)(unsigned flags, yc_u64 priority, yc_u32 voucher)
{
    yc_uintptr_t *tsd = __yc_tsd();
    if (flags & 0x1)
        tsd[YC_TSD_QOS] = priority & ~YC_PP_FLAGS_MASK;
    if (flags & YC_SET_SELF_WQ_KEVENT_UNBIND) {
        int r = YC_KFN(__bsdthread_ctl)(YC_BSDTHREAD_CTL_SET_SELF, (yc_uintptr_t)priority, voucher,
                                        YC_SET_SELF_WQ_KEVENT_UNBIND);
        if (r == 0)
            tsd[YC_TSD_QOS] &= ~(yc_uintptr_t)YC_PP_NEEDS_UNBIND;
    }
    return 0;
}
