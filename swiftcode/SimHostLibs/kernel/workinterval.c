#include "yc_kernel.h"

int mach_vm_allocate(yc_port_t task, yc_u64 *address, yc_u64 size, int flags);
int mach_port_allocate(yc_port_t task, yc_u32 right, yc_port_t *name);
int __work_interval_ctl(yc_u32 operation, yc_u64 work_interval_id, void *arg, yc_size_t len);
int *__error(void);

#define YC_WI_OP_JOIN 5u
#define YC_WI_OP_GET_FLAGS 9u
struct yc_wi_create_params {
    yc_u64 id;
    yc_u32 port;
    yc_u32 flags;
};

static int yc_wi_kernel(yc_u32 operation, yc_u64 id, void *arg, yc_size_t len)
{
    int saved = *__error();
    int r = __work_interval_ctl(operation, id, arg, len);
    if (r != 0) *__error() = saved;
    return r;
}

struct yc_work_interval {
    yc_u64 id;
    yc_u32 flags;
    yc_port_t port;
};

#define YC_WI_POOL 256
static struct yc_work_interval yc_wi_pool[YC_WI_POOL];
static yc_u64 yc_wi_next;

static struct yc_work_interval *yc_wi_alloc(void)
{
    yc_u64 n = __atomic_fetch_add(&yc_wi_next, 1, __ATOMIC_RELAXED);
    if (n < YC_WI_POOL) {
        yc_wi_pool[n].id = n + 1;
        return &yc_wi_pool[n];
    }
    yc_u64 address = 0;
    if (mach_vm_allocate(mach_task_self_, &address, 16384, 1 ) != 0) return YC_NULL;
    struct yc_work_interval *w = (struct yc_work_interval *)(__UINTPTR_TYPE__)address;
    w->id = n + 1;
    return w;
}

YC_EXPORT int work_interval_create(struct yc_work_interval **out, yc_u32 flags)
{
    if (out == YC_NULL) {
        __swiftcode_set_errno(YC_EINVAL);
        return -1;
    }
    struct yc_work_interval *w = yc_wi_alloc();
    if (w == YC_NULL) {
        __swiftcode_set_errno(12 );
        return -1;
    }
    w->flags = flags;
    w->port = YC_MACH_PORT_NULL;
    *out = w;
    return 0;
}

YC_EXPORT int work_interval_destroy(struct yc_work_interval *w)
{
    (void)w;
    return 0;
}

YC_EXPORT int work_interval_join(struct yc_work_interval *w)
{
    (void)w;
    return 0;
}

YC_EXPORT int work_interval_leave(void)
{
    (void)yc_wi_kernel(YC_WI_OP_JOIN, 0, YC_NULL, 0);
    return 0;
}

YC_EXPORT int work_interval_join_port(yc_port_t port)
{
    if (port != YC_MACH_PORT_NULL && port != YC_MACH_PORT_DEAD) (void)yc_wi_kernel(YC_WI_OP_JOIN, port, YC_NULL, 0);
    return 0;
}

YC_EXPORT int work_interval_copy_port(struct yc_work_interval *w, yc_port_t *port)
{
    if (w == YC_NULL || port == YC_NULL) {
        __swiftcode_set_errno(YC_EINVAL);
        return -1;
    }
    if (w->port == YC_MACH_PORT_NULL) {
        yc_port_t p = YC_MACH_PORT_NULL;
        if (mach_port_allocate(mach_task_self_, YC_MACH_PORT_RIGHT_RECEIVE, &p) != 0) {
            __swiftcode_set_errno(YC_ENOTSUP);
            return -1;
        }
        w->port = p;
    }
    if (mach_port_insert_right(mach_task_self_, w->port, w->port, YC_MACH_MSG_TYPE_MAKE_SEND) != 0) {
        __swiftcode_set_errno(YC_ENOTSUP);
        return -1;
    }
    *port = w->port;
    return 0;
}

YC_EXPORT int work_interval_get_flags_from_port(yc_port_t port, yc_u32 *flags)
{
    yc_u32 found = 0;
    if (port != YC_MACH_PORT_NULL && port != YC_MACH_PORT_DEAD) {
        struct yc_wi_create_params p = {0, 0, 0};
        if (yc_wi_kernel(YC_WI_OP_GET_FLAGS, port, &p, sizeof p) == 0) found = p.flags;
    }
    if (flags != YC_NULL) *flags = found;
    return 0;
}

YC_EXPORT int work_interval_notify(struct yc_work_interval *w, yc_u64 start, yc_u64 finish, yc_u64 deadline,
                                   yc_u64 next_start, yc_u32 flags)
{
    (void)w; (void)start; (void)finish; (void)deadline; (void)next_start; (void)flags;
    return 0;
}

YC_EXPORT int work_interval_notify_simple(struct yc_work_interval *w, yc_u64 start, yc_u64 deadline, yc_u64 next_start)
{
    (void)w; (void)start; (void)deadline; (void)next_start;
    return 0;
}
