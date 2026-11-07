#ifndef _TVG_LODEPNG_H_
#define _TVG_LODEPNG_H_

#include <stddef.h>

enum LodePNGColorType
{
    LCT_GREY = 0,
    LCT_RGB = 2,
    LCT_PALETTE = 3,
    LCT_GREY_ALPHA = 4,
    LCT_RGBA = 6,
    LCT_MAX_OCTET_VALUE = 255
};

struct LodePNGDecompressSettings
{
    unsigned ignore_adler32;
    unsigned ignore_nlen;

    unsigned (*custom_zlib)(unsigned char**, size_t*, const unsigned char*, size_t, const LodePNGDecompressSettings*);
    unsigned (*custom_inflate)(unsigned char**, size_t*, const unsigned char*, size_t, const LodePNGDecompressSettings*);

    const void* custom_context;
};

struct LodePNGColorMode
{
    LodePNGColorType colortype;
    unsigned bitdepth;

    unsigned char* palette;
    size_t palettesize;

    unsigned key_defined;
    unsigned key_r;
    unsigned key_g;
    unsigned key_b;
};

struct LodePNGInfo
{
    unsigned compression_method;
    unsigned filter_method;
    unsigned interlace_method;
    LodePNGColorMode color;

    unsigned iccp_defined;
    char* iccp_name;
    unsigned char* iccp_profile;
    unsigned iccp_profile_size;

};

struct LodePNGDecoderSettings
{
    LodePNGDecompressSettings zlibsettings;

    unsigned ignore_crc;
    unsigned ignore_critical;
    unsigned ignore_end;

    unsigned color_convert;
};

struct LodePNGState
{
    LodePNGDecoderSettings decoder;
    LodePNGColorMode info_raw;
    LodePNGInfo info_png;
    unsigned error;
};

void lodepng_state_init(LodePNGState* state);
void lodepng_state_cleanup(LodePNGState* state);
unsigned lodepng_decode(unsigned char** out, unsigned* w, unsigned* h, LodePNGState* state, const unsigned char* in, size_t insize);
unsigned lodepng_inspect(unsigned* w, unsigned* h, LodePNGState* state, const unsigned char* in, size_t insize);
unsigned lodepng_toSrgb(unsigned char* out, const unsigned char* in, unsigned w, unsigned h, const LodePNGState* state);

#endif
