#include "yc_kernel.h"

struct yc_mig_header {
    yc_u32 bits;
    yc_u32 size;
    yc_port_t remote;
    yc_port_t local;
    yc_port_t voucher;
    int id;
};
_Static_assert(sizeof(struct yc_mig_header) == 24, "mach_msg_header_t is 24 bytes");

int mach_msg(void *msg, yc_u32 option, yc_u32 send_size, yc_u32 rcv_size, yc_port_t rcv_name, yc_u32 timeout,
             yc_u32 notify);
yc_port_t mig_get_reply_port(void);
void mig_dealloc_reply_port(yc_port_t reply_port);
void mach_msg_destroy(void *msg);

#define YC_MACH_SEND_MSG 0x00000001u
#define YC_MACH_RCV_MSG 0x00000002u
#define YC_MACH_MSGH_BITS_COMPLEX 0x80000000u
#define YC_MACH_SEND_INVALID_DATA 0x10000002
#define YC_MACH_SEND_INVALID_HEADER 0x10000010
#define YC_MACH_NOTIFY_SEND_ONCE 71

#define YC_MIG_TYPE_ERROR (-300)
#define YC_MIG_REPLY_MISMATCH (-301)
#define YC_MIG_ARRAY_TOO_LARGE (-307)
#define YC_MIG_SERVER_DIED (-308)

static const yc_u8 yc_ndr[8] = {0, 0, 0, 0, 1, 0, 0, 0};

struct yc_mig_reply {
    struct yc_mig_header h;
    yc_u8 ndr[8];
    int ret_code;
    yc_u8 trailer[68];
};

static int mig_simple_rpc(void *msg, yc_u32 send_size, yc_u32 rcv_size, yc_port_t server, int id)
{
    struct yc_mig_header *h = msg;
    yc_port_t reply_port = mig_get_reply_port();
    h->bits = YC_MACH_MSG_TYPE_COPY_SEND | (YC_MACH_MSG_TYPE_MAKE_SEND_ONCE << 8);
    h->size = send_size;
    h->remote = server;
    h->local = reply_port;
    h->voucher = YC_MACH_PORT_NULL;
    h->id = id;
    int kr = mach_msg(h, YC_MACH_SEND_MSG | YC_MACH_RCV_MSG, send_size, rcv_size, reply_port, 0,
                      YC_MACH_PORT_NULL);
    if (kr != YC_KERN_SUCCESS) {
        if (kr != YC_MACH_SEND_INVALID_DATA && kr != YC_MACH_SEND_INVALID_DEST && kr != YC_MACH_SEND_INVALID_HEADER)
            mig_dealloc_reply_port(reply_port);
        return kr;
    }
    const struct yc_mig_reply *r = msg;
    if (r->h.id != id + 100) {
        int err = (r->h.id == YC_MACH_NOTIFY_SEND_ONCE) ? YC_MIG_SERVER_DIED : YC_MIG_REPLY_MISMATCH;
        mach_msg_destroy(msg);
        return err;
    }
    if ((r->h.bits & YC_MACH_MSGH_BITS_COMPLEX) || r->h.size != 36) {
        mach_msg_destroy(msg);
        return YC_MIG_TYPE_ERROR;
    }
    return r->ret_code;
}

static int mig_out32_rpc(void *msg, yc_u32 send_size, yc_u32 rcv_size, yc_port_t server, int id, yc_u32 *out)
{
    struct yc_mig_header *h = msg;
    yc_port_t reply_port = mig_get_reply_port();
    h->bits = YC_MACH_MSG_TYPE_COPY_SEND | (YC_MACH_MSG_TYPE_MAKE_SEND_ONCE << 8);
    h->size = send_size;
    h->remote = server;
    h->local = reply_port;
    h->voucher = YC_MACH_PORT_NULL;
    h->id = id;
    int kr = mach_msg(h, YC_MACH_SEND_MSG | YC_MACH_RCV_MSG, send_size, rcv_size, reply_port, 0,
                      YC_MACH_PORT_NULL);
    if (kr != YC_KERN_SUCCESS) {
        if (kr != YC_MACH_SEND_INVALID_DATA && kr != YC_MACH_SEND_INVALID_DEST && kr != YC_MACH_SEND_INVALID_HEADER)
            mig_dealloc_reply_port(reply_port);
        return kr;
    }
    const struct yc_mig_reply *r = msg;
    if (r->h.id != id + 100) {
        int err = (r->h.id == YC_MACH_NOTIFY_SEND_ONCE) ? YC_MIG_SERVER_DIED : YC_MIG_REPLY_MISMATCH;
        mach_msg_destroy(msg);
        return err;
    }
    if (r->h.bits & YC_MACH_MSGH_BITS_COMPLEX) {
        mach_msg_destroy(msg);
        return YC_MIG_TYPE_ERROR;
    }
    if (r->h.size == 36 && r->ret_code != YC_KERN_SUCCESS)
        return r->ret_code;
    if (r->h.size != 40 || r->ret_code != YC_KERN_SUCCESS)
        return YC_MIG_TYPE_ERROR;
    const yc_u8 *b = (const yc_u8 *)msg + 36;
    *out = (yc_u32)b[0] | ((yc_u32)b[1] << 8) | ((yc_u32)b[2] << 16) | ((yc_u32)b[3] << 24);
    return YC_KERN_SUCCESS;
}

#define YC_MACH_PORT_GET_REFS_ID 3207

YC_EXPORT int mach_port_get_refs(yc_port_t task, yc_port_t name, yc_u32 right, yc_u32 *refs)
{
    union {
        struct {
            struct yc_mig_header h;
            yc_u8 ndr[8];
            yc_port_t name;
            yc_u32 right;
        } req;
        struct yc_mig_reply reply;
    } m;
    for (int i = 0; i < 8; i++)
        m.req.ndr[i] = yc_ndr[i];
    m.req.name = name;
    m.req.right = right;
    yc_u32 value = 0;
    int kr = mig_out32_rpc(&m, 40, (yc_u32)sizeof m, task, YC_MACH_PORT_GET_REFS_ID, &value);
    if (kr == YC_KERN_SUCCESS)
        *refs = value;
    return kr;
}

YC_EXPORT int _kernelrpc_mach_port_get_refs(yc_port_t task, yc_port_t name, yc_u32 right, yc_u32 *refs)
{
    return mach_port_get_refs(task, name, right, refs);
}

#define YC_MACH_PORT_SET_MSCOUNT_ID 3210

YC_EXPORT int mach_port_set_mscount(yc_port_t task, yc_port_t name, yc_u32 mscount)
{
    union {
        struct {
            struct yc_mig_header h;
            yc_u8 ndr[8];
            yc_port_t name;
            yc_u32 mscount;
        } req;
        struct yc_mig_reply reply;
    } m;
    for (int i = 0; i < 8; i++)
        m.req.ndr[i] = yc_ndr[i];
    m.req.name = name;
    m.req.mscount = mscount;
    return mig_simple_rpc(&m, 40, (yc_u32)sizeof m, task, YC_MACH_PORT_SET_MSCOUNT_ID);
}

YC_EXPORT int _kernelrpc_mach_port_set_mscount(yc_port_t task, yc_port_t name, yc_u32 mscount)
{
    return mach_port_set_mscount(task, name, mscount);
}

#define YC_MACH_PORT_SET_ATTRIBUTES_ID 3218
#define YC_MACH_PORT_INFO_MAX 17u

YC_EXPORT int mach_port_set_attributes(yc_port_t task, yc_port_t name, int flavor, const int *info, yc_u32 count)
{
    union {
        struct {
            struct yc_mig_header h;
            yc_u8 ndr[8];
            yc_port_t name;
            int flavor;
            yc_u32 count;
            int info[YC_MACH_PORT_INFO_MAX];
        } req;
        struct yc_mig_reply reply;
    } m;
    _Static_assert(__builtin_offsetof(__typeof__(m.req), info) == 44, "info at 44");
    if (count > YC_MACH_PORT_INFO_MAX)
        return YC_MIG_ARRAY_TOO_LARGE;
    for (int i = 0; i < 8; i++)
        m.req.ndr[i] = yc_ndr[i];
    m.req.name = name;
    m.req.flavor = flavor;
    m.req.count = count;
    for (yc_u32 i = 0; i < count; i++)
        m.req.info[i] = info[i];
    return mig_simple_rpc(&m, 44 + 4 * count, (yc_u32)sizeof m, task, YC_MACH_PORT_SET_ATTRIBUTES_ID);
}

YC_EXPORT int _kernelrpc_mach_port_set_attributes(yc_port_t task, yc_port_t name, int flavor, const int *info,
                                                  yc_u32 count)
{
    return mach_port_set_attributes(task, name, flavor, info, count);
}

YC_EXPORT int host_get_special_port(yc_port_t host_priv, int node, int which, yc_port_t *port)
{
    (void)host_priv;
    (void)node;
    (void)which;
    (void)port;
    return YC_KERN_INVALID_ARGUMENT;
}

YC_EXPORT int host_set_atm_diagnostic_flag(yc_port_t host, yc_u32 diagnostic_flag)
{
    (void)diagnostic_flag;
    return host == 0 ? YC_KERN_INVALID_ARGUMENT : 8 ;
}

YC_EXPORT int host_request_notification(yc_port_t host, int notify_type, yc_port_t notify_port)
{
    if (host == 0 || notify_type < 0 || notify_type > 1)
        return YC_KERN_INVALID_ARGUMENT;
    if (notify_port == 0 || notify_port == 0xFFFFFFFFu)
        return 20;
    return 0;
}

#define YC_MACH_PORT_EXTRACT_RIGHT_ID 3215

YC_EXPORT int mach_port_extract_right(yc_port_t task, yc_port_t name, yc_u32 msgt_name, yc_port_t *poly,
                                      yc_u32 *poly_poly)
{
    union {
        struct {
            struct yc_mig_header h;
            yc_u8 ndr[8];
            yc_port_t name;
            yc_u32 msgt_name;
        } req;
        struct {
            struct yc_mig_header h;
            yc_u32 count;
            yc_port_t port;
            yc_u32 pad1;
            yc_u16 pad2;
            yc_u8 disposition;
            yc_u8 type;
            yc_u8 trailer[68];
        } ok;
        struct yc_mig_reply err;
    } m;
    _Static_assert(__builtin_offsetof(__typeof__(m.ok), trailer) == 40, "port reply is 40 bytes");
    for (int i = 0; i < 8; i++)
        m.req.ndr[i] = yc_ndr[i];
    m.req.name = name;
    m.req.msgt_name = msgt_name;
    struct yc_mig_header *h = &m.req.h;
    yc_port_t reply_port = mig_get_reply_port();
    h->bits = YC_MACH_MSG_TYPE_COPY_SEND | (YC_MACH_MSG_TYPE_MAKE_SEND_ONCE << 8);
    h->size = 40;
    h->remote = task;
    h->local = reply_port;
    h->voucher = YC_MACH_PORT_NULL;
    h->id = YC_MACH_PORT_EXTRACT_RIGHT_ID;
    int kr = mach_msg(h, YC_MACH_SEND_MSG | YC_MACH_RCV_MSG, 40, (yc_u32)sizeof m, reply_port, 0, YC_MACH_PORT_NULL);
    if (kr != YC_KERN_SUCCESS) {
        if (kr != YC_MACH_SEND_INVALID_DATA && kr != YC_MACH_SEND_INVALID_DEST && kr != YC_MACH_SEND_INVALID_HEADER)
            mig_dealloc_reply_port(reply_port);
        return kr;
    }
    if (m.ok.h.id != YC_MACH_PORT_EXTRACT_RIGHT_ID + 100) {
        int err = (m.ok.h.id == YC_MACH_NOTIFY_SEND_ONCE) ? YC_MIG_SERVER_DIED : YC_MIG_REPLY_MISMATCH;
        mach_msg_destroy(&m);
        return err;
    }
    if (!(m.ok.h.bits & YC_MACH_MSGH_BITS_COMPLEX)) {
        if (m.err.h.size == 36 && m.err.ret_code != YC_KERN_SUCCESS)
            return m.err.ret_code;
        mach_msg_destroy(&m);
        return YC_MIG_TYPE_ERROR;
    }
    if (m.ok.h.size != 40 || m.ok.count != 1 || m.ok.type != 0) {
        mach_msg_destroy(&m);
        return YC_MIG_TYPE_ERROR;
    }
    *poly = m.ok.port;
    *poly_poly = m.ok.disposition;
    return YC_KERN_SUCCESS;
}

YC_EXPORT int _kernelrpc_mach_port_extract_right(yc_port_t task, yc_port_t name, yc_u32 msgt_name, yc_port_t *poly,
                                                 yc_u32 *poly_poly)
{
    return mach_port_extract_right(task, name, msgt_name, poly, poly_poly);
}
