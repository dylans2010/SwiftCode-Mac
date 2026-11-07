#ifndef _TVG_SW_RASTER_CORE_H_
#define _TVG_SW_RASTER_CORE_H_

#include "tvgSwCommon.h"

uint32_t cRasterDownScaler(const uint32_t*, uint32_t, uint32_t, uint32_t, float, float, int32_t, int32_t, int32_t);
void cRasterUnpremultiply(uint32_t*, uint32_t);
void cRasterPremultiply(uint32_t*, uint32_t);
void cRasterTranslucentPixels(uint32_t*, uint32_t*, uint32_t, uint8_t);
void cRasterSolidPixels(uint32_t*, uint32_t*, uint32_t, uint8_t);
void cRasterSolidPixel32(uint32_t*, uint32_t, uint32_t, int32_t);
bool cRasterTranslucentRle(SwSurface*, const SwRle*, const RenderRegion&, const RenderColor&);
bool cRasterTranslucentRect(SwSurface*, const RenderRegion&, const RenderColor&);
bool cRasterABGRtoARGB(RenderSurface*);
void cRasterGaussianFilterRow(uint8_t*, const uint8_t*, int32_t, int32_t, float);

#if defined(THORVG_AVX_SUPPORT) || defined(THORVG_NEON_SUPPORT)
    extern uint32_t (*rasterDownScaler)(const uint32_t*, uint32_t, uint32_t, uint32_t, float, float, int32_t, int32_t, int32_t);
    extern void (*rasterUnpremultiply)(uint32_t*, uint32_t);
    extern void (*rasterPremultiply)(uint32_t*, uint32_t);
    extern void (*rasterTranslucentPixels)(uint32_t*, uint32_t*, uint32_t, uint8_t);
    extern void (*rasterSolidPixels)(uint32_t*, uint32_t*, uint32_t, uint8_t);
    extern void (*rasterSolidPixel32)(uint32_t*, uint32_t, uint32_t, int32_t);
    extern bool (*rasterTranslucentRle)(SwSurface*, const SwRle*, const RenderRegion&, const RenderColor&);
    extern bool (*rasterTranslucentRect)(SwSurface*, const RenderRegion&, const RenderColor&);
    extern bool (*rasterABGRtoARGB)(RenderSurface*);
    extern void (*rasterGaussianFilterRow)(uint8_t*, const uint8_t*, int32_t, int32_t, float);
    extern void (*rasterGaussianXYFlipBlock)(const uint32_t*, uint32_t*, int32_t);
#else
    #define rasterDownScaler cRasterDownScaler
    #define rasterUnpremultiply cRasterUnpremultiply
    #define rasterPremultiply cRasterPremultiply
    #define rasterTranslucentPixels cRasterTranslucentPixels
    #define rasterSolidPixels cRasterSolidPixels
    #define rasterSolidPixel32 cRasterSolidPixel32
    #define rasterTranslucentRle cRasterTranslucentRle
    #define rasterTranslucentRect cRasterTranslucentRect
    #define rasterABGRtoARGB cRasterABGRtoARGB
    #define rasterGaussianFilterRow cRasterGaussianFilterRow
#endif

#endif
