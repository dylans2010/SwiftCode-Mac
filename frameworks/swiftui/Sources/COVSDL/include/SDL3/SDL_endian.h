#ifndef SDL_endian_h_
#define SDL_endian_h_

#include <SDL3/SDL_stdinc.h>

#if defined(_MSC_VER) && (_MSC_VER >= 1400)
#if defined(__clang__) && !SDL_HAS_BUILTIN(_m_prefetch)
#ifndef __PRFCHWINTRIN_H
#define __PRFCHWINTRIN_H
static __inline__ void __attribute__((__always_inline__, __nodebug__))
_m_prefetch(void *__P)
{
  __builtin_prefetch(__P, 0, 3 );
}
#endif
#endif

#include <intrin.h>
#endif

#define SDL_LIL_ENDIAN  1234

#define SDL_BIG_ENDIAN  4321

#ifndef SDL_BYTEORDER
#ifdef SDL_WIKI_DOCUMENTATION_SECTION

#define SDL_BYTEORDER   SDL_LIL_ENDIAN___or_maybe___SDL_BIG_ENDIAN
#elif defined(SDL_PLATFORM_LINUX) || defined(__GLIBC__)
#include <endian.h>
#define SDL_BYTEORDER  __BYTE_ORDER
#elif defined(SDL_PLATFORM_SOLARIS)
#include <sys/byteorder.h>
#if defined(_LITTLE_ENDIAN)
#define SDL_BYTEORDER   SDL_LIL_ENDIAN
#elif defined(_BIG_ENDIAN)
#define SDL_BYTEORDER   SDL_BIG_ENDIAN
#else
#error Unsupported endianness
#endif
#elif defined(SDL_PLATFORM_OPENBSD) || defined(__DragonFly__)
#include <endian.h>
#define SDL_BYTEORDER  BYTE_ORDER
#elif defined(SDL_PLATFORM_FREEBSD) || defined(SDL_PLATFORM_NETBSD)
#include <sys/endian.h>
#define SDL_BYTEORDER  BYTE_ORDER
#elif defined(__ORDER_LITTLE_ENDIAN__) && defined(__ORDER_BIG_ENDIAN__) && defined(__BYTE_ORDER__)
#if (__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
#define SDL_BYTEORDER   SDL_LIL_ENDIAN
#elif (__BYTE_ORDER__ == __ORDER_BIG_ENDIAN__)
#define SDL_BYTEORDER   SDL_BIG_ENDIAN
#else
#error Unsupported endianness
#endif
#else
#if defined(__hppa__) || \
    defined(__m68k__) || defined(mc68000) || defined(_M_M68K) || \
    (defined(__MIPS__) && defined(__MIPSEB__)) || \
    defined(__ppc__) || defined(__POWERPC__) || defined(__powerpc__) || defined(__PPC__) || \
    defined(__sparc__) || defined(__sparc)
#define SDL_BYTEORDER   SDL_BIG_ENDIAN
#else
#define SDL_BYTEORDER   SDL_LIL_ENDIAN
#endif
#endif
#endif

#ifndef SDL_FLOATWORDORDER
#ifdef SDL_WIKI_DOCUMENTATION_SECTION

#define SDL_FLOATWORDORDER   SDL_LIL_ENDIAN___or_maybe___SDL_BIG_ENDIAN
#elif defined(__ORDER_LITTLE_ENDIAN__) && defined(__ORDER_BIG_ENDIAN__) && defined(__FLOAT_WORD_ORDER__)
#if (__FLOAT_WORD_ORDER__ == __ORDER_LITTLE_ENDIAN__)
#define SDL_FLOATWORDORDER   SDL_LIL_ENDIAN
#elif (__FLOAT_WORD_ORDER__ == __ORDER_BIG_ENDIAN__)
#define SDL_FLOATWORDORDER   SDL_BIG_ENDIAN
#else
#error Unsupported endianness
#endif
#elif defined(__MAVERICK__)
#define SDL_FLOATWORDORDER   SDL_LIL_ENDIAN
#elif (defined(__arm__) || defined(__thumb__)) && !defined(__VFP_FP__) && !defined(__ARM_EABI__)
#define SDL_FLOATWORDORDER   SDL_BIG_ENDIAN
#else
#define SDL_FLOATWORDORDER   SDL_BYTEORDER
#endif
#endif

#include <SDL3/SDL_begin_code.h>
#ifdef __cplusplus
extern "C" {
#endif

#if defined(__GNUC__) || defined(__clang__)
#   define HAS_BUILTIN_BSWAP16 (SDL_HAS_BUILTIN(__builtin_bswap16)) || \
        (__GNUC__ > 4 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 8))
#   define HAS_BUILTIN_BSWAP32 (SDL_HAS_BUILTIN(__builtin_bswap32)) || \
        (__GNUC__ > 4 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 3))
#   define HAS_BUILTIN_BSWAP64 (SDL_HAS_BUILTIN(__builtin_bswap64)) || \
        (__GNUC__ > 4 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 3))

#   define HAS_BROKEN_BSWAP (__GNUC__ == 2 && __GNUC_MINOR__ <= 95)
#else
#   define HAS_BUILTIN_BSWAP16 0
#   define HAS_BUILTIN_BSWAP32 0
#   define HAS_BUILTIN_BSWAP64 0
#   define HAS_BROKEN_BSWAP 0
#endif

#ifndef SDL_WIKI_DOCUMENTATION_SECTION
#if HAS_BUILTIN_BSWAP16
#define SDL_Swap16(x) __builtin_bswap16(x)
#elif (defined(_MSC_VER) && (_MSC_VER >= 1400)) && !defined(__ICL)
#pragma intrinsic(_byteswap_ushort)
#define SDL_Swap16(x) _byteswap_ushort(x)
#elif defined(__i386__) && !HAS_BROKEN_BSWAP
SDL_FORCE_INLINE Uint16 SDL_Swap16(Uint16 x)
{
  __asm__("xchgb %b0,%h0": "=q"(x):"0"(x));
    return x;
}
#elif defined(__x86_64__)
SDL_FORCE_INLINE Uint16 SDL_Swap16(Uint16 x)
{
  __asm__("xchgb %b0,%h0": "=abcd"(x):"0"(x));
    return x;
}
#elif (defined(__powerpc__) || defined(__ppc__))
SDL_FORCE_INLINE Uint16 SDL_Swap16(Uint16 x)
{
    int result;

  __asm__("rlwimi %0,%2,8,16,23": "=&r"(result):"0"(x >> 8), "r"(x));
    return (Uint16)result;
}
#elif (defined(__m68k__) && !defined(__mcoldfire__))
SDL_FORCE_INLINE Uint16 SDL_Swap16(Uint16 x)
{
  __asm__("rorw #8,%0": "=d"(x): "0"(x):"cc");
    return x;
}
#elif defined(__WATCOMC__) && defined(__386__)
extern __inline Uint16 SDL_Swap16(Uint16);
#pragma aux SDL_Swap16 = \
  "xchg al, ah" \
  parm   [ax]   \
  modify [ax];
#else
SDL_FORCE_INLINE Uint16 SDL_Swap16(Uint16 x)
{
    return SDL_static_cast(Uint16, ((x << 8) | (x >> 8)));
}
#endif
#endif

#ifndef SDL_WIKI_DOCUMENTATION_SECTION
#if HAS_BUILTIN_BSWAP32
#define SDL_Swap32(x) __builtin_bswap32(x)
#elif (defined(_MSC_VER) && (_MSC_VER >= 1400)) && !defined(__ICL)
#pragma intrinsic(_byteswap_ulong)
#define SDL_Swap32(x) _byteswap_ulong(x)
#elif defined(__i386__) && !HAS_BROKEN_BSWAP
SDL_FORCE_INLINE Uint32 SDL_Swap32(Uint32 x)
{
  __asm__("bswap %0": "=r"(x):"0"(x));
    return x;
}
#elif defined(__x86_64__)
SDL_FORCE_INLINE Uint32 SDL_Swap32(Uint32 x)
{
  __asm__("bswapl %0": "=r"(x):"0"(x));
    return x;
}
#elif (defined(__powerpc__) || defined(__ppc__))
SDL_FORCE_INLINE Uint32 SDL_Swap32(Uint32 x)
{
    Uint32 result;

  __asm__("rlwimi %0,%2,24,16,23": "=&r"(result): "0" (x>>24),  "r"(x));
  __asm__("rlwimi %0,%2,8,8,15"  : "=&r"(result): "0" (result), "r"(x));
  __asm__("rlwimi %0,%2,24,0,7"  : "=&r"(result): "0" (result), "r"(x));
    return result;
}
#elif (defined(__m68k__) && !defined(__mcoldfire__))
SDL_FORCE_INLINE Uint32 SDL_Swap32(Uint32 x)
{
  __asm__("rorw #8,%0\n\tswap %0\n\trorw #8,%0": "=d"(x): "0"(x):"cc");
    return x;
}
#elif defined(__WATCOMC__) && defined(__386__)
extern __inline Uint32 SDL_Swap32(Uint32);
#pragma aux SDL_Swap32 = \
  "bswap eax"  \
  parm   [eax] \
  modify [eax];
#else
SDL_FORCE_INLINE Uint32 SDL_Swap32(Uint32 x)
{
    return SDL_static_cast(Uint32, ((x << 24) | ((x << 8) & 0x00FF0000) |
                                    ((x >> 8) & 0x0000FF00) | (x >> 24)));
}
#endif
#endif

#ifndef SDL_WIKI_DOCUMENTATION_SECTION
#if HAS_BUILTIN_BSWAP64
#define SDL_Swap64(x) __builtin_bswap64(x)
#elif (defined(_MSC_VER) && (_MSC_VER >= 1400)) && !defined(__ICL)
#pragma intrinsic(_byteswap_uint64)
#define SDL_Swap64(x) _byteswap_uint64(x)
#elif defined(__i386__) && !HAS_BROKEN_BSWAP
SDL_FORCE_INLINE Uint64 SDL_Swap64(Uint64 x)
{
    union {
        struct {
            Uint32 a, b;
        } s;
        Uint64 u;
    } v;
    v.u = x;
  __asm__("bswapl %0 ; bswapl %1 ; xchgl %0,%1"
          : "=r"(v.s.a), "=r"(v.s.b)
          : "0" (v.s.a),  "1"(v.s.b));
    return v.u;
}
#elif defined(__x86_64__)
SDL_FORCE_INLINE Uint64 SDL_Swap64(Uint64 x)
{
  __asm__("bswapq %0": "=r"(x):"0"(x));
    return x;
}
#elif defined(__WATCOMC__) && defined(__386__)
extern __inline Uint64 SDL_Swap64(Uint64);
#pragma aux SDL_Swap64 = \
  "bswap eax"     \
  "bswap edx"     \
  "xchg eax,edx"  \
  parm [eax edx]  \
  modify [eax edx];
#else
SDL_FORCE_INLINE Uint64 SDL_Swap64(Uint64 x)
{
    Uint32 hi, lo;

    lo = SDL_static_cast(Uint32, x & 0xFFFFFFFF);
    x >>= 32;
    hi = SDL_static_cast(Uint32, x & 0xFFFFFFFF);
    x = SDL_Swap32(lo);
    x <<= 32;
    x |= SDL_Swap32(hi);
    return (x);
}
#endif
#endif

SDL_FORCE_INLINE float SDL_SwapFloat(float x)
{
    union {
        float f;
        Uint32 ui32;
    } swapper;
    swapper.f = x;
    swapper.ui32 = SDL_Swap32(swapper.ui32);
    return swapper.f;
}

#undef HAS_BROKEN_BSWAP
#undef HAS_BUILTIN_BSWAP16
#undef HAS_BUILTIN_BSWAP32
#undef HAS_BUILTIN_BSWAP64

#ifdef SDL_WIKI_DOCUMENTATION_SECTION

SDL_FORCE_INLINE Uint16 SDL_Swap16(Uint16 x) { return x_but_byteswapped; }

SDL_FORCE_INLINE Uint32 SDL_Swap32(Uint32 x) { return x_but_byteswapped; }

SDL_FORCE_INLINE Uint64 SDL_Swap64(Uint64 x) { return x_but_byteswapped; }

#define SDL_Swap16LE(x) SwapOnlyIfNecessary(x)

#define SDL_Swap32LE(x) SwapOnlyIfNecessary(x)

#define SDL_Swap64LE(x) SwapOnlyIfNecessary(x)

#define SDL_SwapFloatLE(x) SwapOnlyIfNecessary(x)

#define SDL_Swap16BE(x) SwapOnlyIfNecessary(x)

#define SDL_Swap32BE(x) SwapOnlyIfNecessary(x)

#define SDL_Swap64BE(x) SwapOnlyIfNecessary(x)

#define SDL_SwapFloatBE(x) SwapOnlyIfNecessary(x)

#elif SDL_BYTEORDER == SDL_LIL_ENDIAN
#define SDL_Swap16LE(x)     (x)
#define SDL_Swap32LE(x)     (x)
#define SDL_Swap64LE(x)     (x)
#define SDL_SwapFloatLE(x)  (x)
#define SDL_Swap16BE(x)     SDL_Swap16(x)
#define SDL_Swap32BE(x)     SDL_Swap32(x)
#define SDL_Swap64BE(x)     SDL_Swap64(x)
#define SDL_SwapFloatBE(x)  SDL_SwapFloat(x)
#else
#define SDL_Swap16LE(x)     SDL_Swap16(x)
#define SDL_Swap32LE(x)     SDL_Swap32(x)
#define SDL_Swap64LE(x)     SDL_Swap64(x)
#define SDL_SwapFloatLE(x)  SDL_SwapFloat(x)
#define SDL_Swap16BE(x)     (x)
#define SDL_Swap32BE(x)     (x)
#define SDL_Swap64BE(x)     (x)
#define SDL_SwapFloatBE(x)  (x)
#endif

#ifdef __cplusplus
}
#endif
#include <SDL3/SDL_close_code.h>

#endif
