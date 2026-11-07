#ifndef OV_COVVULKAN_H
#define OV_COVVULKAN_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ovk_context ovk_context;

typedef struct {
    uint32_t layer;
    float a, b, c, d, tx, ty;
    float opacity;
    int32_t scissor_x, scissor_y, scissor_w, scissor_h;
} ovk_draw;

int ovk_load(char *err, size_t errlen);

ovk_context *ovk_create(const char *const *extensions, uint32_t extension_count, int with_swapchain,
                        char *err, size_t errlen);
void ovk_destroy(ovk_context *c);

const char *ovk_device_name(const ovk_context *c);
int ovk_device_is_cpu(const ovk_context *c);
void *ovk_instance(const ovk_context *c);

int ovk_attach_surface(ovk_context *c, uint64_t surface, uint32_t width, uint32_t height, char *err, size_t errlen);
int ovk_set_offscreen(ovk_context *c, uint32_t width, uint32_t height, char *err, size_t errlen);
int ovk_resize(ovk_context *c, uint32_t width, uint32_t height, char *err, size_t errlen);
void ovk_target_size(const ovk_context *c, uint32_t *width, uint32_t *height);

int ovk_layer_ensure(ovk_context *c, uint32_t layer, uint32_t width, uint32_t height, char *err, size_t errlen);
int ovk_layer_update(ovk_context *c, uint32_t layer, const void *rgba, uint32_t x, uint32_t y, uint32_t w, uint32_t h);
void ovk_layer_release(ovk_context *c, uint32_t layer);

int ovk_frame(ovk_context *c, const ovk_draw *draws, uint32_t draw_count, const float clear[4], int readback,
              char *err, size_t errlen);
int ovk_readback(ovk_context *c, void *rgba, size_t size);

#ifdef __cplusplus
}
#endif

#endif
