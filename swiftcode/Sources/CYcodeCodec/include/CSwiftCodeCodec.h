#ifndef CSWIFTCODE_CODEC_H
#define CSWIFTCODE_CODEC_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int swiftcodec_jpeg_available(void);

int swiftcodec_jpeg_encode_bgra(const uint8_t *pixels, int width, int height, size_t bytesPerRow, int quality,
                            uint8_t **out, size_t *outSize);

int swiftcodec_jpeg_decode_available(void);

int swiftcodec_jpeg_decode_bgra(const uint8_t *data, size_t size, int width, int height, uint8_t *dst, size_t dstBytesPerRow);

int swiftcodec_zlib_available(void);

size_t swiftcodec_zlib_bound(size_t n);

int swiftcodec_zlib_compress(const uint8_t *src, size_t n, int level, uint8_t *dst, size_t *dstSize);

int swiftcodec_zlib_uncompress(const uint8_t *src, size_t n, uint8_t *dst, size_t *dstSize);

uint32_t swiftcodec_crc32(uint32_t crc, const uint8_t *src, size_t n);

void swiftcodec_downscale_bgra(const uint8_t *src, size_t srcBytesPerRow, int srcWidth, int srcHeight, int factor,
                           uint8_t *dst, size_t dstBytesPerRow);

void swiftcodec_free(void *p);

int swiftcodec_opus_available(void);
void *swiftcodec_opus_encoder_new(int sampleRate, int channels, int bitrate);
int swiftcodec_opus_encode(void *encoder, const float *pcm, int frames, uint8_t *out, int maxBytes);
void swiftcodec_opus_encoder_free(void *encoder);
void *swiftcodec_opus_decoder_new(int sampleRate, int channels);
int swiftcodec_opus_decode(void *decoder, const uint8_t *data, int size, float *pcm, int maxFrames, int fec);
void swiftcodec_opus_decoder_free(void *decoder);

void *swiftcodec_pulse_open(const char *app, const char *stream, int sampleRate, int channels, int targetMs);
int swiftcodec_pulse_write(void *stream, const float *pcm, int frames, int channels);
int64_t swiftcodec_pulse_latency_us(void *stream);
void swiftcodec_pulse_close(void *stream);

void swiftcodec_name_thread(const char *name);

#ifdef __cplusplus
}
#endif
#endif
