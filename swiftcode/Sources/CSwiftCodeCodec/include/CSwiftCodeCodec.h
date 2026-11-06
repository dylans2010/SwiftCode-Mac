/* CSwiftCodeCodec: image helpers for the display stream
 * (specs/simulator/display-stream.md §4). JPEG comes from the system's
 * libjpeg (libjpeg-turbo), zlib from the system's libz, both loaded at run
 * time with dlopen: the package builds where neither is installed, and the
 * functions then report "unavailable". */
#ifndef CSWIFTCODE_CODEC_H
#define CSWIFTCODE_CODEC_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 1 when JPEG encoding works here (header at build time, library at run time). */
int swiftcodec_jpeg_available(void);

/* Encodes `width` x `height` BGRA pixels (rows `bytesPerRow` apart) as a
 * baseline JPEG of `quality` (1...100). On success returns 0 and sets *out
 * (free with swiftcodec_free) and *outSize; otherwise returns -1. */
int swiftcodec_jpeg_encode_bgra(const uint8_t *pixels, int width, int height, size_t bytesPerRow, int quality,
                            uint8_t **out, size_t *outSize);

/* 1 when JPEG decoding works here (header at build time, library at run time). */
int swiftcodec_jpeg_decode_available(void);

/* Decodes a baseline JPEG of exactly `width` x `height` pixels into BGRX
 * memory at dst (rows `dstBytesPerRow` apart; the fourth byte is 0xFF).
 * Returns 0, or -1 (unavailable, corrupt, or another size). Thread-safe. */
int swiftcodec_jpeg_decode_bgra(const uint8_t *data, size_t size, int width, int height, uint8_t *dst, size_t dstBytesPerRow);

/* 1 when zlib can be loaded. */
int swiftcodec_zlib_available(void);

/* Worst-case size of compressing n bytes (0 without zlib). */
size_t swiftcodec_zlib_bound(size_t n);

/* zlib-format (RFC 1950) compression of src into dst (capacity *dstSize,
 * at least swiftcodec_zlib_bound(n)). Returns 0 and the compressed size in
 * *dstSize, or -1. */
int swiftcodec_zlib_compress(const uint8_t *src, size_t n, int level, uint8_t *dst, size_t *dstSize);

/* Inflates a zlib-format stream into dst (capacity *dstSize). Returns 0 and
 * the inflated size in *dstSize, or -1. */
int swiftcodec_zlib_uncompress(const uint8_t *src, size_t n, uint8_t *dst, size_t *dstSize);

/* CRC-32 (the zlib/PNG polynomial) of n bytes, continuing from crc (0 to start). */
uint32_t swiftcodec_crc32(uint32_t crc, const uint8_t *src, size_t n);

/* Box-filter downscale of BGRA by an integer factor (1...8). The result is
 * ceil(srcWidth / factor) x ceil(srcHeight / factor); edge cells average
 * the pixels they cover. */
void swiftcodec_downscale_bgra(const uint8_t *src, size_t srcBytesPerRow, int srcWidth, int srcHeight, int factor,
                           uint8_t *dst, size_t dstBytesPerRow);

void swiftcodec_free(void *p);

/* ---- Audio (display-stream.md §15): Opus (libopus) and PulseAudio's simple API, loaded at run time. ---- */

int swiftcodec_opus_available(void);
/* A low-delay encoder (OPUS_APPLICATION_RESTRICTED_LOWDELAY, in-band FEC on), NULL without libopus. */
void *swiftcodec_opus_encoder_new(int sampleRate, int channels, int bitrate);
/* Encodes `frames` interleaved Float32 frames (2.5, 5, 10 or 20 ms); returns the packet's bytes or < 0. */
int swiftcodec_opus_encode(void *encoder, const float *pcm, int frames, uint8_t *out, int maxBytes);
void swiftcodec_opus_encoder_free(void *encoder);
void *swiftcodec_opus_decoder_new(int sampleRate, int channels);
/* Decodes a packet (data NULL: conceal a lost one; fec 1: recover the packet before this one from it);
 * returns frames decoded or < 0. */
int swiftcodec_opus_decode(void *decoder, const uint8_t *data, int size, float *pcm, int maxFrames, int fec);
void swiftcodec_opus_decoder_free(void *decoder);

/* A Float32 playback stream on the default output, `targetMs` of buffering; NULL without a server. */
void *swiftcodec_pulse_open(const char *app, const char *stream, int sampleRate, int channels, int targetMs);
/* Blocks until the frames are queued; 0 on success. */
int swiftcodec_pulse_write(void *stream, const float *pcm, int frames, int channels);
/* The stream's latency (queued + device), microseconds, or -1. */
int64_t swiftcodec_pulse_latency_us(void *stream);
void swiftcodec_pulse_close(void *stream);

/* Names the calling thread (at most 15 bytes are kept). */
void swiftcodec_name_thread(const char *name);

#ifdef __cplusplus
}
#endif
#endif
