#include <cmath>
#include <cstdint>
#include "tvgMath.h"
#include "tvgLodePng.h"

typedef struct
{
    unsigned type;
    float* lut;
    size_t lut_size;
    float gamma;
} LodePNGICCCurve;

typedef struct
{

    float illuminant[3];

    unsigned has_chad;
    Matrix chad;

    unsigned has_whitepoint;
    float white[3];
    unsigned has_chromaticity;
    Matrix rgb;

    unsigned has_trc;

    LodePNGICCCurve trc[3];
} LodePNGICC;

static float _iccForwardTRC(const LodePNGICCCurve* curve, float x)
{
    if (curve->type == 0) {
        return x;
    }
    if (curve->type == 1) {
        float v0, v1, fraction;
        size_t index;
        if (!curve->lut) return 0;
        if (x < 0) return x;
        index = (size_t)(x * (curve->lut_size - 1));
        if (index >= curve->lut_size) return x;

        v0 = curve->lut[index];
        v1 = (index + 1 < curve->lut_size) ? curve->lut[index + 1] : 1.0f;
        fraction = (x * (curve->lut_size - 1)) - index;
        return v0 * (1 - fraction) + v1 * fraction;
    }
    if (curve->type == 2) {
        return (x > 0) ? powf(x, curve->gamma) : x;
    }
    return 0;
}

static uint32_t _decodeICC(const unsigned char* data, size_t size, size_t* pos, uint8_t bytes)
{
    *pos += bytes;
    if (*pos > size) return 0;
    uint32_t value = 0;
    for (auto i = *pos - bytes; i < *pos; ++i) value = (value << 8) | data[i];
    return value;
}

static float _decodeICC15Fixed16(const unsigned char* data, size_t size, size_t* pos)
{
    return static_cast<int32_t>(_decodeICC(data, size, pos, 4)) / 65536.0f;
}

static void _decodeICCXYZ(float* x, float* y, float* z, const unsigned char* data, size_t size, size_t* offset)
{
    *x = _decodeICC15Fixed16(data, size, offset);
    *y = _decodeICC15Fixed16(data, size, offset);
    *z = _decodeICC15Fixed16(data, size, offset);
}

static constexpr unsigned _isICCword(uint32_t value, const char* word)
{
    return value == ((static_cast<uint32_t>(word[0]) << 24) | (static_cast<uint32_t>(word[1]) << 16) |
                     (static_cast<uint32_t>(word[2]) << 8) | static_cast<uint32_t>(word[3]));
}

static unsigned _parseICC(LodePNGICC* icc, const unsigned char* data, size_t size)
{
    size_t pos = 0;

    if (size < 132) return 1;

    pos = 16;
    if (!_isICCword(_decodeICC(data, size, &pos, 4), "RGB ")) return 1;

    pos = 68;
    _decodeICCXYZ(&icc->illuminant[0], &icc->illuminant[1], &icc->illuminant[2], data, size, &pos);

    pos = 128;
    auto numtags = _decodeICC(data, size, &pos, 4);
    if (pos >= size) return 1;
    for (size_t i = 0; i < numtags; i++) {
        auto tag = _decodeICC(data, size, &pos, 4);
        auto offset = static_cast<size_t>(_decodeICC(data, size, &pos, 4));
        auto tagsize = _decodeICC(data, size, &pos, 4);
        if (pos >= size || offset >= size) return 1;
        if (offset + tagsize > size) return 1;
        if (tagsize < 8) return 1;

        if (_isICCword(tag, "wtpt")) {
            offset += 8;
            _decodeICCXYZ(&icc->white[0], &icc->white[1], &icc->white[2], data, size, &offset);
            icc->has_whitepoint = 1;
        } else if (_isICCword(tag, "rXYZ")) {
            offset += 8;
            _decodeICCXYZ(&icc->rgb.e11, &icc->rgb.e21, &icc->rgb.e31, data, size, &offset);
            icc->has_chromaticity = 1;
        } else if (_isICCword(tag, "gXYZ")) {
            offset += 8;
            _decodeICCXYZ(&icc->rgb.e12, &icc->rgb.e22, &icc->rgb.e32, data, size, &offset);
            icc->has_chromaticity = 1;
        } else if (_isICCword(tag, "bXYZ")) {
            offset += 8;
            _decodeICCXYZ(&icc->rgb.e13, &icc->rgb.e23, &icc->rgb.e33, data, size, &offset);
            icc->has_chromaticity = 1;
        } else if (_isICCword(tag, "chad")) {
            offset += 8;
            _decodeICCXYZ(&icc->chad.e11, &icc->chad.e12, &icc->chad.e13, data, size, &offset);
            _decodeICCXYZ(&icc->chad.e21, &icc->chad.e22, &icc->chad.e23, data, size, &offset);
            _decodeICCXYZ(&icc->chad.e31, &icc->chad.e32, &icc->chad.e33, data, size, &offset);
            icc->has_chad = 1;
        } else if (_isICCword(tag, "rTRC") || _isICCword(tag, "gTRC") || _isICCword(tag, "bTRC")) {
            auto channel = _isICCword(tag, "bTRC") ? 2 : (_isICCword(tag, "gTRC") ? 1 : 0);
            if (_isICCword(_decodeICC(data, size, &offset, 4), "curv")) {
                auto trc = &icc->trc[channel];
                icc->has_trc = 1;
                offset += 4;
                auto count = static_cast<size_t>(_decodeICC(data, size, &offset, 4));
                if (count == 0) {
                    trc->type = 0;
                } else if (count == 1) {
                    trc->type = 2;
                    trc->gamma = _decodeICC(data, size, &offset, 2) / 256.0f;
                } else {
                    trc->type = 1;
                    if (offset + count * 2 > size || count > 16777216) return 1;
                    trc->lut = tvg::malloc<float>(count * sizeof(float));
                    if (!trc->lut) return 1;
                    trc->lut_size = count;
                    for (size_t j = 0; j < count; j++) {
                        trc->lut[j] = _decodeICC(data, size, &offset, 2) * (1.0f / 65535.0f);
                    }
                }
            }
        }
        if (offset > size) return 1;
    }

    return 0;
}

static void _mulMatrix(float* x2, float* y2, float* z2, const Matrix& m, float x, float y, float z)
{
    *x2 = x * m.e11 + y * m.e12 + z * m.e13;
    *y2 = x * m.e21 + y * m.e22 + z * m.e23;
    *z2 = x * m.e31 + y * m.e32 + z * m.e33;
}

static unsigned _getChrmMatrixXYZ(Matrix* m, const Matrix& rgb, const float white[3])
{
    float rs, gs, bs;
    if (!inverse(&rgb, m)) return 1;
    _mulMatrix(&rs, &gs, &bs, *m, white[0], white[1], white[2]);
    *m = {
        rs * rgb.e11, gs * rgb.e12, bs * rgb.e13,
        rs * rgb.e21, gs * rgb.e22, bs * rgb.e23,
        rs * rgb.e31, gs * rgb.e32, bs * rgb.e33
    };
    return 0;
}

static void _getAdaptationMatrix(Matrix* m,
                                 float wx0, float wy0, float wz0,
                                 float wx1, float wy1, float wz1)
{
    static const Matrix bradford = {
        0.8951f, 0.2664f, -0.1614f,
        -0.7502f, 1.7135f, 0.0367f,
        0.0389f, -0.0685f, 1.0296f
    };
    static const Matrix bradfordInv = {
        0.9869929f, -0.1470543f, 0.1599627f,
        0.4323053f, 0.5183603f, 0.0492912f,
        -0.0085287f, 0.0400428f, 0.9684867f
    };
    float rho0, gam0, bet0, rho1, gam1, bet1, rho2, gam2, bet2;
    _mulMatrix(&rho0, &gam0, &bet0, bradford, wx0, wy0, wz0);
    _mulMatrix(&rho1, &gam1, &bet1, bradford, wx1, wy1, wz1);
    rho2 = rho1 / rho0;
    gam2 = gam1 / gam0;
    bet2 = bet1 / bet0;
    Matrix scaled = {
        rho2 * bradford.e11, rho2 * bradford.e12, rho2 * bradford.e13,
        gam2 * bradford.e21, gam2 * bradford.e22, gam2 * bradford.e23,
        bet2 * bradford.e31, bet2 * bradford.e32, bet2 * bradford.e33
    };
    *m = bradfordInv * scaled;
}

static unsigned _validateICC(const LodePNGICC* icc)
{
    return icc->has_chromaticity && icc->has_whitepoint && icc->has_trc;
}

static unsigned _getICCChrm(Matrix* m, float whitepoint[3], const LodePNGICC* icc)
{
    Matrix a;
    if (icc->has_chad) {
        if (!inverse(&icc->chad, &a)) return 1;
    } else {
        _getAdaptationMatrix(&a, icc->illuminant[0], icc->illuminant[1], icc->illuminant[2],
                             icc->white[0], icc->white[1], icc->white[2]);
    }
    if (icc->has_chad) {
        _mulMatrix(&whitepoint[0], &whitepoint[1], &whitepoint[2], a, icc->white[0], icc->white[1], icc->white[2]);
    } else {
        whitepoint[0] = icc->white[0];
        whitepoint[1] = icc->white[1];
        whitepoint[2] = icc->white[2];
    }

    auto rgb = a * icc->rgb;

    if (_getChrmMatrixXYZ(m, rgb, whitepoint)) return 1;
    return 0;
}

static unsigned _convertToXYZ_setup(Matrix* source, float whitepoint[3],
                                    float gammatable[3][256], const LodePNGState* state)
{
    LodePNGICC icc = {};
    auto error = _parseICC(&icc, state->info_png.iccp_profile, state->info_png.iccp_profile_size);
    if (error || !_validateICC(&icc)) {
        error = 1;
        goto cleanup;
    }

    for (size_t c = 0; c < 3; c++) {
        for (size_t i = 0; i < 256; i++) {
            gammatable[c][i] = _iccForwardTRC(&icc.trc[c], i * (1.0f / 255.0f));
        }
    }

    error = _getICCChrm(source, whitepoint, &icc);

cleanup:
    for (auto& trc : icc.trc) tvg::free(trc.lut);
    return error;
}

static unsigned _convertFromXYZ_setup(Matrix* target, const float whitepoint[3])
{
    Matrix srgb = {
        0.4124564f, 0.3575761f, 0.1804375f,
        0.2126729f, 0.7151522f, 0.0721750f,
        0.0193339f, 0.1191920f, 0.9503041f
    };
    static const float srgbWhitepoint[3] = {0.9504559270516716f, 1.0f, 1.0890577507598784f};

    if (!inverse(&srgb, target)) return 1;

    Matrix adaptation;
    _getAdaptationMatrix(&adaptation,
                         whitepoint[0], whitepoint[1], whitepoint[2],
                         srgbWhitepoint[0], srgbWhitepoint[1], srgbWhitepoint[2]);

    *target = *target * adaptation;
    return 0;
}

static inline void _convertRGBPixel(unsigned char* out, const unsigned char* in,
                                    const Matrix& transform, const float gammatable[3][256])
{
    float rgb[3];
    _mulMatrix(&rgb[0], &rgb[1], &rgb[2], transform,
               gammatable[0][in[0]], gammatable[1][in[1]], gammatable[2][in[2]]);

    for (size_t c = 0; c < 3; c++) {
        auto& v = rgb[c];
        v = (v < 0.0031308f) ? (v * 12.92f) : (1.055f * powf(v, 1 / 2.4f) - 0.055f);

        out[c] = static_cast<unsigned char>(0.5f + 255.0f * std::min(std::max(0.0f, v), 1.0f));
    }
    out[3] = in[3];
}

unsigned lodepng_toSrgb(unsigned char* out, const unsigned char* in, unsigned w, unsigned h, const LodePNGState* state_in)
{

    Matrix source;
    float whitepoint[3], gammatable[3][256];
    auto error = _convertToXYZ_setup(&source, whitepoint, gammatable, state_in);
    if (error) return error;

    Matrix transform;
    error = _convertFromXYZ_setup(&transform, whitepoint);
    if (error) return error;

    transform = transform * source;

    for (size_t i = 0, n = static_cast<size_t>(w) * h; i < n; i++) {
        _convertRGBPixel(out, in, transform, gammatable);
        out += 4;
        in += 4;
    }

    return 0;
}
