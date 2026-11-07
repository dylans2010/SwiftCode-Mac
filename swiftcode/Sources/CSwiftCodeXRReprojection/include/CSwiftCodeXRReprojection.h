#ifndef CSWIFTCODE_XR_REPROJECTION_H
#define CSWIFTCODE_XR_REPROJECTION_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    void *get_instance_proc_addr;
    void *instance;
    void *physical_device;
    void *device;
    uint32_t queue_family;
    void *queue;
    int anisotropy;
} yrp_vulkan;

typedef struct yrp_context yrp_context;

yrp_context *yrp_create(const yrp_vulkan *vk, char *error, size_t error_size);
void yrp_destroy(yrp_context *c);

int yrp_set_colour(yrp_context *c, const void *bgra, int width, int height, int stride);

enum { YRP_NV12 = 0, YRP_YUV444 = 1 };
int yrp_set_colour_yuv(yrp_context *c, int format, const uint8_t *y, const uint8_t *u, const uint8_t *v, int pitch, int width, int height);
int yrp_set_colour_nv12(yrp_context *c, const uint8_t *y, const uint8_t *uv, int pitch, int width, int height);

int yrp_read_colour(yrp_context *c, void *bgra, size_t size);

int yrp_set_depth(yrp_context *c, const uint16_t *q, int width, int height);

int yrp_set_inset(yrp_context *c, const void *bgra, int width, int height, int stride,
                  int x, int y, int w, int h, int full_width, int full_height);

int yrp_set_environment(yrp_context *c, const void *faces, int format, int size);

int yrp_set_environment_depth(yrp_context *c, const uint16_t *q, int n);

int yrp_cache_enable(yrp_context *c, int face_size);
int yrp_cache_clear(yrp_context *c);

enum { YRP_MODE_STRETCH = 0, YRP_MODE_BACKGROUND = 1, YRP_MODE_DISCARD = 2 };

typedef struct {
    float matrix[16];
    float tangents[4];
    float near_distance;
    float edge_ratio;
    int grid_step;
    int mode;
} yrp_params;

int yrp_cache_update(yrp_context *c, const yrp_params *fresh, const float face_matrix[6][16], unsigned face_mask);

typedef struct {
    uint64_t image;
    int64_t format;
    uint32_t width, height;
    uint64_t depth_image;
} yrp_target;

typedef struct {
    int fresh_enabled;
    yrp_params fresh;
    float fade;
    unsigned env_mask;
    float env_matrix[6][16];
    float env_gain;
    unsigned cache_mask;
    float cache_matrix[6][16];
    int fresh_under;
} yrp_frame;

int yrp_render(yrp_context *c, const yrp_target *t, const yrp_frame *f);

int yrp_wait(yrp_context *c);

int yrp_read(yrp_context *c, void *bgra, size_t size);

double yrp_gpu_ms(yrp_context *c);
const char *yrp_device_name(yrp_context *c);
const char *yrp_error(yrp_context *c);

#ifdef __cplusplus
}
#endif

#endif
