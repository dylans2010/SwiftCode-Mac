#include "ycl.h"
#include "yc_dyld_api.h"
#include "yc_macho.h"

extern const struct yc_dyld_api *swiftcode_dyld_api;

static intptr_t image_slide(const struct yc_mach_header_64 *mh) {
    const uint8_t *at = (const uint8_t *)(mh + 1);
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        const struct yc_load_command *lc = (const void *)at;
        if (lc->cmd == YC_LC_SEGMENT_64) {
            const struct yc_segment_command_64 *seg = (const void *)at;
            if (seg->fileoff == 0 && seg->filesize != 0) return (intptr_t)mh - (intptr_t)seg->vmaddr;
        }
        at += lc->cmdsize;
    }
    return 0;
}

static int name_is(const char *field, const char *name) {
    for (int i = 0; i < 16; i++) {
        if (field[i] != name[i]) return 0;
        if (!name[i]) return 1;
    }
    return name[16] == 0;
}

static const struct yc_segment_command_64 *find_segment(const struct yc_mach_header_64 *mh, const char *segname) {
    const uint8_t *at = (const uint8_t *)(mh + 1);
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        const struct yc_load_command *lc = (const void *)at;
        if (lc->cmd == YC_LC_SEGMENT_64) {
            const struct yc_segment_command_64 *seg = (const void *)at;
            if (name_is(seg->segname, segname)) return seg;
        }
        at += lc->cmdsize;
    }
    return 0;
}

static const struct yc_section_64 *find_section(const struct yc_mach_header_64 *mh, const char *segname,
                                                const char *sectname) {
    const struct yc_segment_command_64 *seg = find_segment(mh, segname);
    if (!seg) return 0;
    const struct yc_section_64 *sect = (const void *)(seg + 1);
    for (uint32_t j = 0; j < seg->nsects; j++)
        if (name_is(sect[j].sectname, sectname)) return &sect[j];
    return 0;
}

YCL_EXPORT uint8_t *getsectiondata(const struct yc_mach_header_64 *mh, const char *segname, const char *sectname,
                                   unsigned long *size) {
    const struct yc_section_64 *sect = find_section(mh, segname, sectname);
    if (!sect) {
        if (size) *size = 0;
        return 0;
    }
    if (size) *size = sect->size;
    return (uint8_t *)(sect->addr + image_slide(mh));
}

YCL_EXPORT uint8_t *getsegmentdata(const struct yc_mach_header_64 *mh, const char *segname, unsigned long *size) {
    const struct yc_segment_command_64 *seg = find_segment(mh, segname);
    if (!seg) {
        if (size) *size = 0;
        return 0;
    }
    if (size) *size = seg->vmsize;
    return (uint8_t *)(seg->vmaddr + image_slide(mh));
}

YCL_EXPORT const struct yc_section_64 *getsectbynamefromheader_64(const struct yc_mach_header_64 *mh,
                                                                 const char *segname, const char *sectname) {
    return find_section(mh, segname, sectname);
}

const struct yc_mach_header_64 *ycl_image_containing(const void *address) {
    if (!swiftcode_dyld_api) return 0;
    uint32_t count = swiftcode_dyld_api->image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct yc_mach_header_64 *mh = swiftcode_dyld_api->image_header(i);
        intptr_t slide = image_slide(mh);
        const uint8_t *at = (const uint8_t *)(mh + 1);
        for (uint32_t c = 0; c < mh->ncmds; c++) {
            const struct yc_load_command *lc = (const void *)at;
            if (lc->cmd == YC_LC_SEGMENT_64) {
                const struct yc_segment_command_64 *seg = (const void *)at;
                uintptr_t start = (uintptr_t)(seg->vmaddr + slide);
                if (seg->vmsize && !name_is(seg->segname, "__PAGEZERO") && (uintptr_t)address >= start &&
                    (uintptr_t)address < start + seg->vmsize)
                    return mh;
            }
            at += lc->cmdsize;
        }
    }
    return 0;
}

struct dyld_unwind_sections {
    const void *mh;
    const void *dwarf_section;
    uintptr_t dwarf_section_length;
    const void *compact_unwind_section;
    uintptr_t compact_unwind_section_length;
};

YCL_EXPORT int _dyld_find_unwind_sections(void *address, struct dyld_unwind_sections *info) {
    const struct yc_mach_header_64 *mh = ycl_image_containing(address);
    if (!mh) return 0;
    unsigned long size = 0;
    info->mh = mh;
    info->dwarf_section = getsectiondata(mh, "__TEXT", "__eh_frame", &size);
    info->dwarf_section_length = size;
    info->compact_unwind_section = getsectiondata(mh, "__TEXT", "__unwind_info", &size);
    info->compact_unwind_section_length = size;
    return 1;
}

YCL_EXPORT const void *_dyld_get_image_header_containing_address(const void *address) {
    return ycl_image_containing(address);
}

void *pthread_self(void);
void *pthread_get_stackaddr_np(void *);
size_t pthread_get_stacksize_np(void *);

YCL_EXPORT int backtrace(void **buffer, int size) {
    void *self = pthread_self();
    uintptr_t top = (uintptr_t)pthread_get_stackaddr_np(self);
    uintptr_t bottom = top - pthread_get_stacksize_np(self);
    uintptr_t fp = (uintptr_t)__builtin_frame_address(0);
    int n = 0;
    while (n < size && fp >= bottom && fp + 16 <= top && (fp & 7) == 0) {
        uintptr_t next = ((uintptr_t *)fp)[0];
        uintptr_t lr = ((uintptr_t *)fp)[1];
        if (!lr) break;
        buffer[n++] = (void *)lr;
        if (next <= fp) break;
        fp = next;
    }
    return n;
}

YCL_EXPORT char **backtrace_symbols(void *const *buffer, int size) {
    enum { LINE = 256 };
    char **out = malloc((size_t)size * (sizeof(char *) + LINE));
    if (!out) return 0;
    char *text = (char *)(out + size);
    for (int i = 0; i < size; i++) {
        struct yc_dl_info info = {0, 0, 0, 0};
        int found = swiftcode_dyld_api && swiftcode_dyld_api->dladdr(buffer[i], &info);
        const char *image = found && info.dli_fname ? strrchr(info.dli_fname, '/') : 0;
        image = image ? image + 1 : (found && info.dli_fname ? info.dli_fname : "???");
        out[i] = text + i * LINE;
        if (found && info.dli_sname)
            snprintf(out[i], LINE, "%-3d %-35s 0x%016lx %s + %lu", i, image, (unsigned long)buffer[i], info.dli_sname,
                     (unsigned long)((uintptr_t)buffer[i] - (uintptr_t)info.dli_saddr));
        else
            snprintf(out[i], LINE, "%-3d %-35s 0x%016lx", i, image, (unsigned long)buffer[i]);
    }
    return out;
}

YCL_EXPORT void backtrace_symbols_fd(void *const *buffer, int size, int fd) {
    char **lines = backtrace_symbols(buffer, size);
    if (!lines) return;
    for (int i = 0; i < size; i++) {
        write(fd, lines[i], strlen(lines[i]));
        write(fd, "\n", 1);
    }
    free(lines);
}

int fprintf(FILE *, const char *, ...);

YCL_EXPORT void __assert_rtn(const char *function, const char *file, int line, const char *expression) {
    if (function)
        fprintf(__stderrp, "Assertion failed: (%s), function %s, file %s, line %d.\n", expression, function, file,
                line);
    else
        fprintf(__stderrp, "Assertion failed: (%s), file %s, line %d.\n", expression, file, line);
    abort();
}

YCL_EXPORT int asl_log(void *client, void *message, int level, const char *format, ...) {
    (void)client;
    (void)message;
    (void)level;
    (void)format;
    return 0;
}

#define YCL_MACOS_VERSION ((27u << 16) | (0u << 8) | 0u)

struct ycl_build_version {
    uint32_t platform;
    uint32_t version;
};

YCL_EXPORT int _availability_version_check(uint32_t count, const struct ycl_build_version *versions) {
    for (uint32_t i = 0; i < count; i++)
        if (versions[i].platform == YC_PLATFORM_MACOS && versions[i].version > YCL_MACOS_VERSION) return 0;
    return 1;
}

struct ycl_os_version {
    long major, minor, patch;
};

YCL_EXPORT struct ycl_os_version os_system_version_get_current_version(void) {
    struct ycl_os_version v = {YCL_MACOS_VERSION >> 16, (YCL_MACOS_VERSION >> 8) & 0xFF, YCL_MACOS_VERSION & 0xFF};
    return v;
}

YCL_EXPORT int _dyld_is_objc_constant(int kind, const void *address) {
    (void)kind;
    (void)address;
    return 0;
}
