#ifndef YC_DYLD_API_H
#define YC_DYLD_API_H

#include <stdint.h>

#define YC_DYLD_API_VERSION 1

struct yc_dl_info {
    const char *dli_fname;
    void *dli_fbase;
    const char *dli_sname;
    void *dli_saddr;
};

struct yc_dyld_api {
    unsigned long version;
    uint32_t (*image_count)(void);
    const void *(*image_header)(uint32_t index);
    const char *(*image_name)(uint32_t index);
    intptr_t (*image_slide)(uint32_t index);
    void *(*dlopen)(const char *path, int mode);
    void *(*dlsym)(void *handle, const char *name);
    int (*dlclose)(void *handle);
    const char *(*dlerror)(void);
    int (*dladdr)(const void *address, struct yc_dl_info *info);
    void (*add_image_callback)(void (*callback)(const void *header, intptr_t slide));
    const char *executable_path;
};

#endif
