#ifdef SDL_begin_code_h
#error Nested inclusion of SDL_begin_code.h
#endif
#define SDL_begin_code_h

#ifdef SDL_WIKI_DOCUMENTATION_SECTION

#define SDL_DEPRECATED __attribute__((deprecated))

#define SDL_DECLSPEC __attribute__ ((visibility("default")))

#define SDLCALL __cdecl

#define SDL_INLINE __inline

#define SDL_FORCE_INLINE __forceinline

#define SDL_NORETURN __attribute__((noreturn))

#define SDL_ANALYZER_NORETURN __attribute__((analyzer_noreturn))

#define SDL_FALLTHROUGH [[fallthrough]]

#define SDL_NODISCARD [[nodiscard]]

#define SDL_MALLOC __declspec(allocator) __desclspec(restrict)

#define SDL_ALLOC_SIZE(p) __attribute__((alloc_size(p)))

#define SDL_RESTRICT __restrict

#define SDL_HAS_BUILTIN(x) __has_builtin(x)

#define SDL_ALIGNED(x) __attribute__((aligned(x)))

#endif

#ifndef SDL_RESTRICT
#  if defined(restrict) || ((defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L)))
#    define SDL_RESTRICT restrict
#  elif defined(_MSC_VER) || defined(__GNUC__) || defined(__clang__)
#    define SDL_RESTRICT __restrict
#  else
#    define SDL_RESTRICT
#  endif
#endif

#ifndef SDL_HAS_BUILTIN
#ifdef __has_builtin
#define SDL_HAS_BUILTIN(x) __has_builtin(x)
#else
#define SDL_HAS_BUILTIN(x) 0
#endif
#endif

#ifndef SDL_DEPRECATED
#  if defined(__GNUC__) && (__GNUC__ >= 4)
#    define SDL_DEPRECATED __attribute__((deprecated))
#  elif defined(_MSC_VER)
#    define SDL_DEPRECATED __declspec(deprecated)
#  else
#    define SDL_DEPRECATED
#  endif
#endif

#ifndef SDL_UNUSED
#  ifdef __GNUC__
#    define SDL_UNUSED __attribute__((unused))
#  else
#    define SDL_UNUSED
#  endif
#endif

#ifndef SDL_DECLSPEC
# if defined(SDL_PLATFORM_WINDOWS)
#  ifdef DLL_EXPORT
#   define SDL_DECLSPEC __declspec(dllexport)
#  else
#   define SDL_DECLSPEC
#  endif
# else
#  if defined(__GNUC__) && __GNUC__ >= 4
#   define SDL_DECLSPEC __attribute__ ((visibility("default")))
#  else
#   define SDL_DECLSPEC
#  endif
# endif
#endif

#ifndef SDLCALL
#if defined(SDL_PLATFORM_WINDOWS) && !defined(__GNUC__)
#define SDLCALL __cdecl
#else
#define SDLCALL
#endif
#endif

#if defined(_MSC_VER) || defined(__MWERKS__) || defined(__BORLANDC__)
#ifdef _MSC_VER
#pragma warning(disable: 4103)
#endif
#ifdef __clang__
#pragma clang diagnostic ignored "-Wpragma-pack"
#endif
#ifdef __BORLANDC__
#pragma nopackwarning
#endif
#ifdef _WIN64
#pragma pack(push,8)
#else
#pragma pack(push,4)
#endif
#endif

#ifndef SDL_INLINE
#ifdef __GNUC__
#define SDL_INLINE __inline__
#elif defined(_MSC_VER) || defined(__BORLANDC__) || \
      defined(__DMC__) || defined(__SC__) || \
      defined(__WATCOMC__) || defined(__LCC__) || \
      defined(__DECC) || defined(__CC_ARM)
#define SDL_INLINE __inline
#ifndef __inline__
#define __inline__ __inline
#endif
#else
#define SDL_INLINE inline
#ifndef __inline__
#define __inline__ inline
#endif
#endif
#endif

#ifndef SDL_FORCE_INLINE
#if defined(_MSC_VER) && (_MSC_VER >= 1200)
#define SDL_FORCE_INLINE __forceinline
#elif ( (defined(__GNUC__) && (__GNUC__ >= 4)) || defined(__clang__) )
#define SDL_FORCE_INLINE __attribute__((always_inline)) static __inline__
#else
#define SDL_FORCE_INLINE static SDL_INLINE
#endif
#endif

#ifndef SDL_NORETURN
#if defined(__GNUC__)
#define SDL_NORETURN __attribute__((noreturn))
#elif defined(_MSC_VER)
#define SDL_NORETURN __declspec(noreturn)
#else
#define SDL_NORETURN
#endif
#endif

#ifdef __clang__
#if __has_feature(attribute_analyzer_noreturn)
#define SDL_ANALYZER_NORETURN __attribute__((analyzer_noreturn))
#endif
#endif

#ifndef SDL_ANALYZER_NORETURN
#define SDL_ANALYZER_NORETURN
#endif

#ifndef __MACH__
#ifndef NULL
#ifdef __cplusplus
#define NULL 0
#else
#define NULL ((void *)0)
#endif
#endif
#endif

#ifndef SDL_FALLTHROUGH
#if (defined(__cplusplus) && __cplusplus >= 201703L) || \
    (defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202000L)
#define SDL_FALLTHROUGH [[fallthrough]]
#else
#if defined(__has_attribute) && !defined(__SUNPRO_C) && !defined(__SUNPRO_CC)
#define SDL_HAS_FALLTHROUGH __has_attribute(__fallthrough__)
#else
#define SDL_HAS_FALLTHROUGH 0
#endif
#if SDL_HAS_FALLTHROUGH && \
   ((defined(__GNUC__) && __GNUC__ >= 7) || \
    (defined(__clang_major__) && __clang_major__ >= 10))
#define SDL_FALLTHROUGH __attribute__((__fallthrough__))
#else
#define SDL_FALLTHROUGH do {} while (0)
#endif
#undef SDL_HAS_FALLTHROUGH
#endif
#endif

#ifndef SDL_NODISCARD
#if (defined(__cplusplus) && __cplusplus >= 201703L) || \
    (defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202311L)
#define SDL_NODISCARD [[nodiscard]]
#elif ( (defined(__GNUC__) && (__GNUC__ >= 4)) || defined(__clang__) )
#define SDL_NODISCARD __attribute__((warn_unused_result))
#elif defined(_MSC_VER) && (_MSC_VER >= 1700)
#define SDL_NODISCARD _Check_return_
#else
#define SDL_NODISCARD
#endif
#endif

#ifndef SDL_MALLOC
#if defined(__GNUC__) && (__GNUC__ >= 3)
#define SDL_MALLOC __attribute__((malloc))
#else
#define SDL_MALLOC
#endif
#endif

#ifndef SDL_ALLOC_SIZE
#if (defined(__clang__) && __clang_major__ >= 4) || (defined(__GNUC__) && (__GNUC__ > 4 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 3)))
#define SDL_ALLOC_SIZE(p) __attribute__((alloc_size(p)))
#elif defined(_MSC_VER)
#define SDL_ALLOC_SIZE(p)
#else
#define SDL_ALLOC_SIZE(p)
#endif
#endif

#ifndef SDL_ALLOC_SIZE2
#if (defined(__clang__) && __clang_major__ >= 4) || (defined(__GNUC__) && (__GNUC__ > 4 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 3)))
#define SDL_ALLOC_SIZE2(p1, p2) __attribute__((alloc_size(p1, p2)))
#elif defined(_MSC_VER)
#define SDL_ALLOC_SIZE2(p1, p2)
#else
#define SDL_ALLOC_SIZE2(p1, p2)
#endif
#endif

#ifndef SDL_ALIGNED
#if defined(__clang__) || defined(__GNUC__)
#define SDL_ALIGNED(x) __attribute__((aligned(x)))
#elif defined(_MSC_VER)
#define SDL_ALIGNED(x) __declspec(align(x))
#elif defined(__cplusplus) && (__cplusplus >= 201103L)
#define SDL_ALIGNED(x) alignas(x)
#elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
#define SDL_ALIGNED(x) _Alignas(x)
#else
#define SDL_ALIGNED(x) PLEASE_DEFINE_SDL_ALIGNED
#endif
#endif
