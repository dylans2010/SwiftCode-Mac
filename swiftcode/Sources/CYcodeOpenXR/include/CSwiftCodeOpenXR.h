#ifndef CSWIFTCODE_OPENXR_H
#define CSWIFTCODE_OPENXR_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct { float x, y, z; } yxr_vec3;
typedef struct { float x, y, z, w; } yxr_quat;
typedef struct { yxr_vec3 position; yxr_quat orientation; } yxr_pose;
typedef struct { float angle_left, angle_right, angle_up, angle_down; } yxr_fov;

enum { YXR_JOINTS = 26 };

typedef struct {
    char runtime[128];
    uint32_t runtime_version;
    char system_name[256];
    uint32_t vendor_id;
    int has_eye_gaze, has_hand_tracking, has_hand_interaction, has_fb_eye_social, has_touch_pro;
    int eye_gaze_supported, hand_tracking_supported;
    uint32_t view_count;
    uint32_t recommended_width[2], recommended_height[2], max_width[2], max_height[2];
    uint32_t max_layers;
    char gpu_name[256];
    uint32_t gpu_vendor;
    int64_t swapchain_format;
    int swapchain_bgra;
    int space;
    int blend_modes;
    char extensions[4096];
} yxr_info;

typedef struct {
    int64_t display_time;
    int64_t display_period;
    int should_render;
    int focused;
    int views_valid;
    yxr_pose view_pose[2];
    yxr_fov view_fov[2];
    int head_valid;
    yxr_pose head;
    int gaze_valid;
    yxr_pose gaze;
    int64_t gaze_time;
    int gaze_tracked;
    int hand_valid[2];
    yxr_pose joint[2][YXR_JOINTS];
    float joint_radius[2][YXR_JOINTS];
    uint32_t joint_valid[2];
    int aim_valid[2], grip_valid[2];
    yxr_pose aim[2], grip[2];
    float trigger[2], squeeze[2], stick_x[2], stick_y[2];
    int stick_click[2];
    int button_lower[2];
    int button_upper[2];
    int button_menu;
    int controller_active[2];
    int hand_profile_active[2];
} yxr_frame;

enum {
    YXR_EVENT_NONE = 0,
    YXR_EVENT_STATE = 1,
    YXR_EVENT_RECENTER = 2,
    YXR_EVENT_PROFILE = 3,
    YXR_EVENT_EXIT = 4,
    YXR_EVENT_LOST = 5,
};

typedef struct { int kind; int64_t value; } yxr_event;

typedef struct yxr_session yxr_session;

int yxr_available(char *error, size_t error_size);

yxr_session *yxr_open(const char *app_name, int session, yxr_info *info, char *error, size_t error_size);

int yxr_poll(yxr_session *s, yxr_event *event);

int yxr_running(yxr_session *s);

int yxr_begin_frame(yxr_session *s, yxr_frame *frame);

int yxr_upload(yxr_session *s, int eye, const void *bgra, int width, int height, int stride);

int yxr_upload_nv12(yxr_session *s, int eye, const uint8_t *y, const uint8_t *uv, int pitch, int width, int height);

int yxr_upload_yuv444(yxr_session *s, int eye, const uint8_t *y, const uint8_t *u, const uint8_t *v, int pitch, int width, int height);

void yxr_convert_yuv444(const uint8_t *y, const uint8_t *u, const uint8_t *v, int pitch, int width, int height, uint8_t *dst, int bgra);
void yxr_convert_nv12(const uint8_t *y, const uint8_t *uv, int pitch, int width, int height, uint8_t *dst, int bgra);

void yxr_set_gaze_at_present(yxr_session *s, int on);

typedef struct { yxr_pose pose; float size; int image; } yxr_sprite;

enum { YXR_MAX_SPRITES = 120 };

typedef struct {
    int submit;
    int image[2];
    yxr_pose pose[2];
    yxr_fov fov[2];
    int render[2];
    int depth_valid[2];
    float depth_near, depth_far;
    int inset;
    int inset_image[2];
    yxr_fov inset_fov[2];
    const yxr_sprite *sprites;
    int sprite_count;
} yxr_submit;

int yxr_end_frame(yxr_session *s, const yxr_submit *submit);

void yxr_request_exit(yxr_session *s);

void yxr_close(yxr_session *s);

typedef struct {
    void *instance;
    void *physical_device;
    void *device;
    uint32_t queue_family;
    void *queue;
    void *get_instance_proc_addr;
    int64_t color_format;
    uint32_t recommended_width, recommended_height;
    int anisotropy;
} yxr_vulkan_handles;

int yxr_vulkan(yxr_session *s, yxr_vulkan_handles *out);

int yxr_acquire_render(yxr_session *s, int eye, uint64_t *image, int *width, int *height, int64_t *format);
int yxr_release_render(yxr_session *s, int eye);

int yxr_has_depth_layers(yxr_session *s);
int yxr_acquire_depth(yxr_session *s, int eye, uint64_t *image, int *width, int *height, int64_t *format);
int yxr_release_depth(yxr_session *s, int eye);

void yxr_queue_lock(yxr_session *s);
void yxr_queue_unlock(yxr_session *s);

int64_t yxr_now(yxr_session *s);

const char *yxr_last_error(yxr_session *s);

#ifdef __cplusplus
}
#endif

#endif
