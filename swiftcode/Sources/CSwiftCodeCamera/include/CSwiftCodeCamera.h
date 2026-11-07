#ifndef CSWIFTCODE_CAMERA_H
#define CSWIFTCODE_CAMERA_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char driver[16];
    char card[32];
    char bus_info[32];
    uint32_t version;
    uint32_t capabilities;
    uint32_t device_caps;
} ycam_caps;

typedef struct {
    uint32_t width, height, pixelformat, bytesperline, sizeimage;
    uint32_t field, colorspace, ycbcr_enc, quantization, xfer_func;
} ycam_format;

typedef struct {
    uint32_t index;
    uint32_t bytesused;
    uint32_t flags;
    uint32_t sequence;
    int64_t timestamp_ns;
} ycam_dequeued;

int ycam_open(const char *path);
void ycam_close(int fd);

int ycam_query_caps(int fd, ycam_caps *out);

int ycam_enum_format(int fd, uint32_t index, uint32_t *pixelformat, uint32_t *flags, char description[32]);

int ycam_enum_framesize(int fd, uint32_t pixelformat, uint32_t index, uint32_t *type, uint32_t v[6]);

int ycam_enum_frameinterval(int fd, uint32_t pixelformat, uint32_t width, uint32_t height, uint32_t index,
                            uint32_t *type, uint32_t v[6]);

int ycam_set_format(int fd, ycam_format *f, int try_only);
int ycam_get_format(int fd, ycam_format *f);

int ycam_set_interval(int fd, uint32_t *num, uint32_t *den);

int ycam_request_buffers(int fd, uint32_t count);
int ycam_map_buffer(int fd, uint32_t index, void **address, uint32_t *length);
void ycam_unmap_buffer(void *address, uint32_t length);
int ycam_queue(int fd, uint32_t index);
int ycam_dequeue(int fd, ycam_dequeued *out);
int ycam_stream(int fd, int on);
int ycam_wait(int fd, int timeout_ms);

int64_t ycam_monotonic_ns(void);

typedef struct ycam_jpeg ycam_jpeg;

ycam_jpeg *ycam_jpeg_new(void);
void ycam_jpeg_free(ycam_jpeg *decoder);

int ycam_jpeg_decode(ycam_jpeg *decoder, const uint8_t *data, size_t size);

typedef struct {
    int width, height, components;
    int h[3], v[3], hmax, vmax;
    const uint8_t *plane[3];
    int stride[3];
} ycam_jpeg_image;
void ycam_jpeg_image_info(const ycam_jpeg *decoder, ycam_jpeg_image *out);

typedef struct {
    const uint8_t *y, *cb, *cr;
    int ystep, cstep;
    size_t ystride, cstride;
    int hsub, vsub;
    int width, height;
    int full_range;
    int matrix;
} ycam_ycbcr_source;

void ycam_to_biplanar420(const ycam_ycbcr_source *s, uint8_t *y, size_t ystride, uint8_t *cbcr, size_t cstride,
                         int out_full_range);

void ycam_to_bgra(const ycam_ycbcr_source *s, uint8_t *bgra, size_t stride);

void ycam_ycbcr_to_bgr(int y, int cb, int cr, int full_range, int matrix, uint8_t bgr[3]);

uint8_t ycam_map_luma(int value, int from_full, int to_full);
uint8_t ycam_map_chroma(int value, int from_full, int to_full);

void ycam_bgra_downscale(const uint8_t *src, int width, int height, size_t stride, int factor, uint8_t *dst,
                         size_t dst_stride);

#ifdef __cplusplus
}
#endif

#endif
