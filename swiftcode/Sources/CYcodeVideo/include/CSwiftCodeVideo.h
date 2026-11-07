#ifndef CSWIFTCODE_VIDEO_H
#define CSWIFTCODE_VIDEO_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct yvid_enc yvid_enc;
typedef struct yvid_dec yvid_dec;

enum { YVID_H264 = 0, YVID_HEVC = 1, YVID_AV1 = 2 };
enum { YVID_NV12 = 0, YVID_YUV444 = 1 };

typedef struct { int supported, yuv444, tenBit, maxWidth, maxHeight; } yvid_enc_caps;

int yvid_enc_query(int codec, yvid_enc_caps *caps, char *error, size_t errorSize);

typedef struct { int codec, yuv444, fps, bitrateKbps, qp, constantBitrate; } yvid_enc_params;

int yvid_enc_available(void);

yvid_enc *yvid_enc_open(int width, int height, int fps, int bitrateKbps, char *error, size_t errorSize);

int yvid_enc_encode(yvid_enc *e, const uint8_t *bgra, size_t stride, const int32_t *rects, int count, int forceIDR,
                    const uint8_t **out, size_t *outSize, int *isIDR);

yvid_enc *yvid_enc_open2(int width, int height, const yvid_enc_params *params, char *error, size_t errorSize);

void yvid_enc_close(yvid_enc *e);

int yvid_dec_available(void);

yvid_dec *yvid_dec_open(char *error, size_t errorSize);

int yvid_dec_decode(yvid_dec *d, const uint8_t *au, size_t size, const uint8_t **y, const uint8_t **uv,
                    int *width, int *height, int *pitch);

void yvid_dec_close(yvid_dec *d);

typedef struct { int supported, maxWidth, maxHeight; } yvid_dec_caps;
int yvid_dec_query(int codec, int yuv444, int bitDepth, yvid_dec_caps *caps);

typedef struct { int format; const uint8_t *y, *u, *v; int pitch, width, height; } yvid_picture;

yvid_dec *yvid_dec_open2(int codec, char *error, size_t errorSize);

int yvid_dec_decode2(yvid_dec *d, const uint8_t *au, size_t size, yvid_picture *out);

void yvid_nv12_to_bgrx(const uint8_t *y, const uint8_t *uv, int pitch, int width, int height, uint8_t *dst, size_t dstStride);

void yvid_yuv444_to_bgrx(const uint8_t *y, const uint8_t *u, const uint8_t *v, int pitch, int width, int height, uint8_t *dst, size_t dstStride);

#ifdef __cplusplus
}
#endif
#endif
