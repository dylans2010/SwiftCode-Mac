#include "yc_kernel.h"

#define YC_AT_FDCWD (-2)
#define YC_FD_SETSIZE 1024

YC_NORETURN void __abort_with_payload(yc_u32 reason_namespace, yc_u64 reason_code, void *payload,
                                      yc_u32 payload_size, const char *reason_string, yc_u64 reason_flags);
int __terminate_with_payload(int pid, yc_u32 reason_namespace, yc_u64 reason_code, void *payload,
                             yc_u32 payload_size, const char *reason_string, yc_u64 reason_flags);
int __kdebug_trace(yc_u32 debugid, yc_u64 arg1, yc_u64 arg2, yc_u64 arg3, yc_u64 arg4);
int clonefileat(int src_dirfd, const char *src, int dst_dirfd, const char *dst, yc_u32 flags);
int renameatx_np(int fromfd, const char *from, int tofd, const char *to, yc_u32 flags);
yc_u64 __memorystatus_available_memory(void);

YC_EXPORT YC_NORETURN void abort_with_reason(yc_u32 reason_namespace, yc_u64 reason_code, const char *reason_string,
                                             yc_u64 reason_flags)
{
    __abort_with_payload(reason_namespace, reason_code, YC_NULL, 0, reason_string, reason_flags);
}

YC_EXPORT int terminate_with_reason(int pid, yc_u32 reason_namespace, yc_u64 reason_code, const char *reason_string,
                                    yc_u64 reason_flags)
{
    return __terminate_with_payload(pid, reason_namespace, reason_code, YC_NULL, 0, reason_string, reason_flags);
}

YC_EXPORT int clonefile(const char *src, const char *dst, yc_u32 flags)
{
    return clonefileat(YC_AT_FDCWD, src, YC_AT_FDCWD, dst, flags);
}

YC_EXPORT int renamex_np(const char *from, const char *to, yc_u32 flags)
{
    return renameatx_np(YC_AT_FDCWD, from, YC_AT_FDCWD, to, flags);
}

YC_EXPORT int sem_init(void *sem, int pshared, unsigned value)
{
    (void)sem;
    (void)pshared;
    (void)value;
    __swiftcode_set_errno(YC_ENOSYS);
    return -1;
}

YC_EXPORT int sem_destroy(void *sem)
{
    (void)sem;
    __swiftcode_set_errno(YC_ENOSYS);
    return -1;
}

YC_EXPORT int __darwin_check_fd_set_overflow(int fd, const void *set, int unlimited)
{
    (void)set;
    return fd >= 0 && (unlimited || fd < YC_FD_SETSIZE);
}

YC_EXPORT int kdebug_is_enabled(yc_u32 debugid)
{
    (void)debugid;
    return yc_commpage_u32(YC_COMM_KDEBUG_ENABLE) != 0;
}

YC_EXPORT int kdebug_trace(yc_u32 debugid, yc_u64 arg1, yc_u64 arg2, yc_u64 arg3, yc_u64 arg4)
{
    if (yc_commpage_u32(YC_COMM_KDEBUG_ENABLE) == 0)
        return 0;
    return __kdebug_trace(debugid, arg1, arg2, arg3, arg4);
}

YC_EXPORT yc_size_t os_proc_available_memory(void)
{
    yc_u64 v = __memorystatus_available_memory();
    return v == ~(yc_u64)0 ? 0 : (yc_size_t)v;
}

int __getpid(void);
__attribute__((visibility("hidden"))) int yc_cached_pid;

YC_EXPORT int getpid(void)
{
    int pid = __atomic_load_n(&yc_cached_pid, __ATOMIC_RELAXED);
    if (pid <= 0) {
        pid = __getpid();
        if (pid > 0)
            __atomic_store_n(&yc_cached_pid, pid, __ATOMIC_RELAXED);
    }
    return pid;
}

static inline yc_u32 yc_bsd0_u32(long number)
{
    register yc_uintptr_t x0 __asm__("x0");
    register long x16 __asm__("x16") = number;
    __asm__ volatile("svc #0x80" : "=r"(x0), "+r"(x16) : : "x1", "memory", "cc");
    return (yc_u32)x0;
}

static inline yc_u32 yc_credential(unsigned index, long number)
{
    if (yc_commpage_u8(YC_COMM_FAST_FLAGS) & YC_FAST_CRED_BLOCK)
        return yc_commpage_u32(YC_COMM_CREDENTIALS + 4 * index);
    return yc_bsd0_u32(number);
}

YC_EXPORT yc_u32 getuid(void) { return yc_credential(0, 24); }
YC_EXPORT yc_u32 geteuid(void) { return yc_credential(1, 25); }
YC_EXPORT yc_u32 getgid(void) { return yc_credential(2, 47); }
YC_EXPORT yc_u32 getegid(void) { return yc_credential(3, 43); }

int __access_extended(const void *entries, yc_size_t size, int *results, yc_u32 uid);

YC_EXPORT int accessx_np(const void *entries, yc_size_t size, int *results, yc_u32 uid)
{
    return __access_extended(entries, size, results, uid);
}

int __iopolicysys(int cmd, void *param);

struct yc_iopol_param {
    int scope;
    int iotype;
    int policy;
};

YC_EXPORT int setiopolicy_np(int iotype, int scope, int policy)
{
    struct yc_iopol_param p = {scope, iotype, policy};
    return __iopolicysys(0, &p);
}

YC_EXPORT int getiopolicy_np(int iotype, int scope)
{
    struct yc_iopol_param p = {scope, iotype, 0};
    if (__iopolicysys(1, &p) != 0)
        return -1;
    return p.policy;
}

YC_EXPORT int madvise(void *addr, yc_size_t len, int advice)
{
    if (yc_commpage_u8(YC_COMM_FAST_FLAGS) & YC_FAST_LOCAL_CALLS) {
        if (advice >= 0 && advice <= 10)
            return 0;
        if (advice != 11) {
            __swiftcode_set_errno(22);
            return -1;
        }
    }
    register yc_uintptr_t x0 __asm__("x0") = (yc_uintptr_t)addr;
    register yc_uintptr_t x1 __asm__("x1") = (yc_uintptr_t)len;
    register yc_uintptr_t x2 __asm__("x2") = (yc_uintptr_t)(long)advice;
    register long x16 __asm__("x16") = 75;
    yc_uintptr_t failed;
    __asm__ volatile("svc #0x80\n\tcset %[f], cs"
                     : "+r"(x0), "+r"(x1), "+r"(x2), "+r"(x16), [f] "=r"(failed)
                     :
                     : "memory", "cc");
    if (failed) {
        __swiftcode_set_errno((int)x0);
        return -1;
    }
    return (int)x0;
}

YC_EXPORT int posix_madvise(void *addr, yc_size_t len, int advice)
{
    return madvise(addr, len, advice);
}

int __csrctl(yc_u32 op, void *buffer, yc_size_t size);
YC_EXPORT int csr_check(yc_u32 mask)
{
    return __csrctl(0, &mask, sizeof(mask));
}

YC_EXPORT int csr_get_active_config(yc_u32 *config)
{
    return __csrctl(1, config, sizeof(*config));
}

int __persona(yc_u32 op, yc_u32 flags, void *info, yc_u32 *id, yc_size_t *idlen, char *path);

struct yc_kpersona_info {
    yc_u32 version;
    yc_u32 id;
    int type;
    yc_u32 gid;
    yc_u32 ngroups;
    yc_u32 groups[16];
    yc_u32 gmuid;
    char name[255 + 1];
    yc_u32 uid;
} __attribute__((packed));
_Static_assert(sizeof(struct yc_kpersona_info) == 348, "struct kpersona_info is 348 bytes");

YC_EXPORT int kpersona_alloc(void *info, yc_u32 *id)
{
    yc_size_t idlen = 1;
    return __persona(1, 0, info, id, &idlen, YC_NULL);
}

YC_EXPORT int kpersona_palloc(void *info, yc_u32 *id, char *path)
{
    yc_size_t idlen = 1;
    return __persona(2, 0, info, id, &idlen, path);
}

YC_EXPORT int kpersona_dealloc(yc_u32 id)
{
    yc_size_t idlen = 1;
    return __persona(3, 0, YC_NULL, &id, &idlen, YC_NULL);
}

YC_EXPORT int kpersona_get(yc_u32 *id)
{
    yc_size_t idlen = 1;
    return __persona(4, 0, YC_NULL, id, &idlen, YC_NULL);
}

YC_EXPORT int kpersona_info(yc_u32 id, void *info)
{
    yc_size_t idlen = 1;
    return __persona(5, 0, info, &id, &idlen, YC_NULL);
}

YC_EXPORT int kpersona_pidinfo(int pid, void *info)
{
    yc_size_t idlen = 1;
    yc_u32 id = (yc_u32)pid;
    return __persona(6, 0, info, &id, &idlen, YC_NULL);
}

YC_EXPORT int kpersona_getpath(yc_u32 id, char *path)
{
    yc_size_t idlen = 1;
    return __persona(8, 0, YC_NULL, &id, &idlen, path);
}

static int yc_persona_find(yc_u32 op, const char *name, yc_u32 uid, int type, yc_u32 *id, yc_size_t *idlen)
{
    struct yc_kpersona_info k;
    char *p = (char *)&k;
    for (yc_size_t i = 0; i < sizeof(k); i++)
        p[i] = 0;
    k.version = 1;
    k.id = uid;
    k.type = type;
    if (name != YC_NULL) {
        yc_size_t i = 0;
        for (; name[i] != 0 && i < sizeof(k.name) - 1; i++)
            k.name[i] = name[i];
    }
    int ret = __persona(op, 0, &k, id, idlen, YC_NULL);
    if (ret < 0)
        return ret;
    return (int)*idlen;
}

YC_EXPORT int kpersona_find(const char *name, yc_u32 uid, yc_u32 *id, yc_size_t *idlen)
{
    return yc_persona_find(7, name, uid, 0, id, idlen);
}

YC_EXPORT int kpersona_find_by_type(int persona_type, yc_u32 *id, yc_size_t *idlen)
{
    return yc_persona_find(9, YC_NULL, (yc_u32)-1, persona_type, id, idlen);
}

static const char *const yc_kern_errors[] = {
    "(os/kern) successful", "(os/kern) invalid address", "(os/kern) protection failure",
    "(os/kern) no space available", "(os/kern) invalid argument", "(os/kern) failure",
    "(os/kern) resource shortage", "(os/kern) not receiver", "(os/kern) no access", "(os/kern) memory failure",
    "(os/kern) memory error", "(os/kern) already in set", "(os/kern) not in set", "(os/kern) name exists",
    "(os/kern) aborted", "(os/kern) invalid name", "(os/kern) invalid task", "(os/kern) invalid right",
    "(os/kern) invalid value", "(os/kern) urefs overflow", "(os/kern) invalid capability",
    "(os/kern) right exists", "(os/kern) invalid host", "(os/kern) memory present",
    "(os/kern) memory data moved", "(os/kern) memory restart copy", "(os/kern) invalid processor set",
    "(os/kern) policy limit", "(os/kern) invalid policy", "(os/kern) invalid object",
    "(os/kern) already waiting", "(os/kern) default set", "(os/kern) exception protected",
    "(os/kern) invalid ledger", "(os/kern) invalid memory control", "(os/kern) invalid security",
    "(os/kern) not depressed", "(os/kern) object terminated", "(os/kern) lock set destroyed",
    "(os/kern) lock unstable", "(os/kern) lock owned by another", "(os/kern) lock owned by self",
    "(os/kern) semaphore destroyed", "(os/kern) RPC terminated", "(os/kern) terminate orphan",
    "(os/kern) let orphan continue", "(os/kern) service not supported", "(os/kern) remote node down",
    "(os/kern) thread not waiting", "(os/kern) operation timed out", "(os/kern) code signing error",
    "(os/kern) policy is static", "(os/kern) insufficient input buffer size",
    "(os/kern) denied by security policy", "(os/kern) missing kernel collection",
    "(os/kern) invalid kernel collection", "(os/kern) result not found",
};

YC_EXPORT const char *mach_error_string(int error_value)
{
    unsigned code = (unsigned)error_value;
    if (code < sizeof(yc_kern_errors) / sizeof(yc_kern_errors[0]))
        return yc_kern_errors[code];
    return "unknown error code";
}
