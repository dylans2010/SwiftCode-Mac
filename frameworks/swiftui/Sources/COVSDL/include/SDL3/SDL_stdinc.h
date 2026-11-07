#ifndef SDL_stdinc_h_
#define SDL_stdinc_h_

#include <SDL3/SDL_platform_defines.h>

#include <stdarg.h>
#include <string.h>
#include <wchar.h>

#if defined(_MSC_VER) && (_MSC_VER < 1600)
typedef signed __int8 int8_t;
typedef unsigned __int8 uint8_t;
typedef signed __int16 int16_t;
typedef unsigned __int16 uint16_t;
typedef signed __int32 int32_t;
typedef unsigned __int32 uint32_t;
typedef signed __int64 int64_t;
typedef unsigned __int64 uint64_t;
#ifndef _INTPTR_T_DEFINED
#ifdef _WIN64
typedef __int64 intptr_t;
#else
typedef int intptr_t;
#endif
#endif
#ifndef _UINTPTR_T_DEFINED
#ifdef _WIN64
typedef unsigned __int64 uintptr_t;
#else
typedef unsigned int uintptr_t;
#endif
#endif
#else
#include <stdint.h>
#endif

#if (defined(__STDC_VERSION__) && __STDC_VERSION__ >= 199901L) || \
    defined(SDL_INCLUDE_INTTYPES_H)
#include <inttypes.h>
#endif

#ifndef __cplusplus
#if defined(__has_include) && !defined(SDL_INCLUDE_STDBOOL_H)
#if __has_include(<stdbool.h>)
#define SDL_INCLUDE_STDBOOL_H
#endif
#endif
#if (defined(__STDC_VERSION__) && __STDC_VERSION__ >= 199901L) || \
    (defined(_MSC_VER) && (_MSC_VER >= 1910 )) || \
    defined(SDL_INCLUDE_STDBOOL_H)
#include <stdbool.h>
#elif !defined(__bool_true_false_are_defined) && !defined(bool)
#define bool  unsigned char
#define false 0
#define true  1
#define __bool_true_false_are_defined 1
#endif
#endif

#ifndef SDL_DISABLE_ALLOCA
# ifndef alloca
#  ifdef HAVE_ALLOCA_H
#   include <alloca.h>
#  elif defined(SDL_PLATFORM_NETBSD)
#   if defined(__STRICT_ANSI__)
#    define SDL_DISABLE_ALLOCA
#   else
#    include <stdlib.h>
#   endif
#  elif defined(__GNUC__)
#   define alloca __builtin_alloca
#  elif defined(_MSC_VER)
#   include <malloc.h>
#   define alloca _alloca
#  elif defined(__WATCOMC__)
#   include <malloc.h>
#  elif defined(__BORLANDC__)
#   include <malloc.h>
#  elif defined(__DMC__)
#   include <stdlib.h>
#  elif defined(SDL_PLATFORM_AIX)
# pragma alloca
#  elif defined(__MRC__)
void *alloca(unsigned);
#  else
void *alloca(size_t);
#  endif
# endif
#endif

#ifdef SDL_WIKI_DOCUMENTATION_SECTION

#define SDL_NOLONGLONG 1

#elif defined(_MSC_VER) && (_MSC_VER < 1310)
#  define SDL_NOLONGLONG 1
#endif

#ifdef SDL_WIKI_DOCUMENTATION_SECTION

#define SDL_SIZE_MAX SIZE_MAX

#elif defined(SIZE_MAX)
# define SDL_SIZE_MAX SIZE_MAX
#else
# define SDL_SIZE_MAX ((size_t) -1)
#endif

#ifndef SDL_COMPILE_TIME_ASSERT
#ifdef SDL_WIKI_DOCUMENTATION_SECTION

#define SDL_COMPILE_TIME_ASSERT(name, x) FailToCompileIf_x_IsFalse(x)
#elif defined(__cplusplus)
#if (__cplusplus >= 201103L)
#define SDL_COMPILE_TIME_ASSERT(name, x)  static_assert(x, #x)
#endif
#elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 202311L)
#define SDL_COMPILE_TIME_ASSERT(name, x)  static_assert(x, #x)
#elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
#define SDL_COMPILE_TIME_ASSERT(name, x) _Static_assert(x, #x)
#endif
#endif

#ifndef SDL_COMPILE_TIME_ASSERT
#define SDL_COMPILE_TIME_ASSERT(name, x)               \
       typedef int SDL_compile_time_assert_ ## name[(x) * 2 - 1]
#endif

#define SDL_arraysize(array) (sizeof(array)/sizeof(array[0]))

#define SDL_STRINGIFY_ARG(arg)  #arg

#ifdef SDL_WIKI_DOCUMENTATION_SECTION

#define SDL_reinterpret_cast(type, expression) reinterpret_cast<type>(expression)

#define SDL_static_cast(type, expression) static_cast<type>(expression)

#define SDL_const_cast(type, expression) const_cast<type>(expression)

#elif defined(__cplusplus)
#define SDL_reinterpret_cast(type, expression) reinterpret_cast<type>(expression)
#define SDL_static_cast(type, expression) static_cast<type>(expression)
#define SDL_const_cast(type, expression) const_cast<type>(expression)
#else
#define SDL_reinterpret_cast(type, expression) ((type)(expression))
#define SDL_static_cast(type, expression) ((type)(expression))
#define SDL_const_cast(type, expression) ((type)(expression))
#endif

#define SDL_FOURCC(A, B, C, D) \
    ((SDL_static_cast(Uint32, SDL_static_cast(Uint8, (A))) << 0) | \
     (SDL_static_cast(Uint32, SDL_static_cast(Uint8, (B))) << 8) | \
     (SDL_static_cast(Uint32, SDL_static_cast(Uint8, (C))) << 16) | \
     (SDL_static_cast(Uint32, SDL_static_cast(Uint8, (D))) << 24))

#ifdef SDL_WIKI_DOCUMENTATION_SECTION

#define SDL_SINT64_C(c)  c ## LL

#define SDL_UINT64_C(c)  c ## ULL

#else

#ifndef SDL_SINT64_C
#if defined(INT64_C)
#define SDL_SINT64_C(c)  INT64_C(c)
#elif defined(_MSC_VER)
#define SDL_SINT64_C(c)  c ## i64
#elif defined(__LP64__) || defined(_LP64)
#define SDL_SINT64_C(c)  c ## L
#else
#define SDL_SINT64_C(c)  c ## LL
#endif
#endif

#ifndef SDL_UINT64_C
#if defined(UINT64_C)
#define SDL_UINT64_C(c)  UINT64_C(c)
#elif defined(_MSC_VER)
#define SDL_UINT64_C(c)  c ## ui64
#elif defined(__LP64__) || defined(_LP64)
#define SDL_UINT64_C(c)  c ## UL
#else
#define SDL_UINT64_C(c)  c ## ULL
#endif
#endif

#endif

typedef int8_t Sint8;
#define SDL_MAX_SINT8   ((Sint8)0x7F)
#define SDL_MIN_SINT8   ((Sint8)(~0x7F))

typedef uint8_t Uint8;
#define SDL_MAX_UINT8   ((Uint8)0xFF)
#define SDL_MIN_UINT8   ((Uint8)0x00)

typedef int16_t Sint16;
#define SDL_MAX_SINT16  ((Sint16)0x7FFF)
#define SDL_MIN_SINT16  ((Sint16)(~0x7FFF))

typedef uint16_t Uint16;
#define SDL_MAX_UINT16  ((Uint16)0xFFFF)
#define SDL_MIN_UINT16  ((Uint16)0x0000)

typedef int32_t Sint32;
#define SDL_MAX_SINT32  ((Sint32)0x7FFFFFFF)
#define SDL_MIN_SINT32  ((Sint32)(~0x7FFFFFFF))

typedef uint32_t Uint32;
#define SDL_MAX_UINT32  ((Uint32)0xFFFFFFFFu)
#define SDL_MIN_UINT32  ((Uint32)0x00000000)

typedef int64_t Sint64;
#define SDL_MAX_SINT64  SDL_SINT64_C(0x7FFFFFFFFFFFFFFF)
#define SDL_MIN_SINT64  ~SDL_SINT64_C(0x7FFFFFFFFFFFFFFF)

typedef uint64_t Uint64;
#define SDL_MAX_UINT64  SDL_UINT64_C(0xFFFFFFFFFFFFFFFF)
#define SDL_MIN_UINT64  SDL_UINT64_C(0x0000000000000000)

typedef Sint64 SDL_Time;
#define SDL_MAX_TIME SDL_MAX_SINT64
#define SDL_MIN_TIME SDL_MIN_SINT64

#ifdef FLT_EPSILON
#define SDL_FLT_EPSILON FLT_EPSILON
#else

#define SDL_FLT_EPSILON 1.1920928955078125e-07F
#endif

#ifdef SDL_WIKI_DOCUMENTATION_SECTION

#define SDL_PRIs64 "lld"

#define SDL_PRIu64 "llu"

#define SDL_PRIx64 "llx"

#define SDL_PRIX64 "llX"

#define SDL_PRIs32 "d"

#define SDL_PRIu32 "u"

#define SDL_PRIx32 "x"

#define SDL_PRIX32 "X"

#define SDL_PRILL_PREFIX "ll"

#define SDL_PRILLd SDL_PRILL_PREFIX "d"

#define SDL_PRILLu SDL_PRILL_PREFIX "u"

#define SDL_PRILLx SDL_PRILL_PREFIX "x"

#define SDL_PRILLX SDL_PRILL_PREFIX "X"
#endif

#ifndef SDL_PRIs64
#if defined(SDL_PLATFORM_WINDOWS)
#define SDL_PRIs64 "I64d"
#elif defined(PRId64)
#define SDL_PRIs64 PRId64
#elif defined(__LP64__) && !defined(SDL_PLATFORM_APPLE) && !defined(__EMSCRIPTEN__)
#define SDL_PRIs64 "ld"
#else
#define SDL_PRIs64 "lld"
#endif
#endif
#ifndef SDL_PRIu64
#if defined(SDL_PLATFORM_WINDOWS)
#define SDL_PRIu64 "I64u"
#elif defined(PRIu64)
#define SDL_PRIu64 PRIu64
#elif defined(__LP64__) && !defined(SDL_PLATFORM_APPLE) && !defined(__EMSCRIPTEN__)
#define SDL_PRIu64 "lu"
#else
#define SDL_PRIu64 "llu"
#endif
#endif
#ifndef SDL_PRIx64
#if defined(SDL_PLATFORM_WINDOWS)
#define SDL_PRIx64 "I64x"
#elif defined(PRIx64)
#define SDL_PRIx64 PRIx64
#elif defined(__LP64__) && !defined(SDL_PLATFORM_APPLE)
#define SDL_PRIx64 "lx"
#else
#define SDL_PRIx64 "llx"
#endif
#endif
#ifndef SDL_PRIX64
#if defined(SDL_PLATFORM_WINDOWS)
#define SDL_PRIX64 "I64X"
#elif defined(PRIX64)
#define SDL_PRIX64 PRIX64
#elif defined(__LP64__) && !defined(SDL_PLATFORM_APPLE)
#define SDL_PRIX64 "lX"
#else
#define SDL_PRIX64 "llX"
#endif
#endif
#ifndef SDL_PRIs32
#ifdef PRId32
#define SDL_PRIs32 PRId32
#else
#define SDL_PRIs32 "d"
#endif
#endif
#ifndef SDL_PRIu32
#ifdef PRIu32
#define SDL_PRIu32 PRIu32
#else
#define SDL_PRIu32 "u"
#endif
#endif
#ifndef SDL_PRIx32
#ifdef PRIx32
#define SDL_PRIx32 PRIx32
#else
#define SDL_PRIx32 "x"
#endif
#endif
#ifndef SDL_PRIX32
#ifdef PRIX32
#define SDL_PRIX32 PRIX32
#else
#define SDL_PRIX32 "X"
#endif
#endif
#ifdef SDL_PLATFORM_WINDOWS
#ifndef SDL_NOLONGLONG
SDL_COMPILE_TIME_ASSERT(longlong_size64, sizeof(long long) == 8);
#endif
#define SDL_PRILL_PREFIX "I64"
#else
#define SDL_PRILL_PREFIX "ll"
#endif
#ifndef SDL_PRILLd
#define SDL_PRILLd SDL_PRILL_PREFIX "d"
#endif
#ifndef SDL_PRILLu
#define SDL_PRILLu SDL_PRILL_PREFIX "u"
#endif
#ifndef SDL_PRILLx
#define SDL_PRILLx SDL_PRILL_PREFIX "x"
#endif
#ifndef SDL_PRILLX
#define SDL_PRILLX SDL_PRILL_PREFIX "X"
#endif

#ifdef SDL_WIKI_DOCUMENTATION_SECTION

#define SDL_IN_BYTECAP(x) _In_bytecount_(x)

#define SDL_INOUT_Z_CAP(x) _Inout_z_cap_(x)

#define SDL_OUT_Z_CAP(x) _Out_z_cap_(x)

#define SDL_OUT_CAP(x) _Out_cap_(x)

#define SDL_OUT_BYTECAP(x) _Out_bytecap_(x)

#define SDL_OUT_Z_BYTECAP(x) _Out_z_bytecap_(x)

#define SDL_PRINTF_FORMAT_STRING _Printf_format_string_

#define SDL_SCANF_FORMAT_STRING _Scanf_format_string_impl_

#define SDL_PRINTF_VARARG_FUNC( fmtargnumber ) __attribute__ (( format( __printf__, fmtargnumber, fmtargnumber+1 )))

#define SDL_PRINTF_VARARG_FUNCV( fmtargnumber ) __attribute__(( format( __printf__, fmtargnumber, 0 )))

#define SDL_SCANF_VARARG_FUNC( fmtargnumber ) __attribute__ (( format( __scanf__, fmtargnumber, fmtargnumber+1 )))

#define SDL_SCANF_VARARG_FUNCV( fmtargnumber ) __attribute__(( format( __scanf__, fmtargnumber, 0 )))

#define SDL_WPRINTF_VARARG_FUNC( fmtargnumber )

#define SDL_WPRINTF_VARARG_FUNCV( fmtargnumber )

#elif defined(SDL_DISABLE_ANALYZE_MACROS)
#define SDL_IN_BYTECAP(x)
#define SDL_INOUT_Z_CAP(x)
#define SDL_OUT_Z_CAP(x)
#define SDL_OUT_CAP(x)
#define SDL_OUT_BYTECAP(x)
#define SDL_OUT_Z_BYTECAP(x)
#define SDL_PRINTF_FORMAT_STRING
#define SDL_SCANF_FORMAT_STRING
#define SDL_PRINTF_VARARG_FUNC( fmtargnumber )
#define SDL_PRINTF_VARARG_FUNCV( fmtargnumber )
#define SDL_SCANF_VARARG_FUNC( fmtargnumber )
#define SDL_SCANF_VARARG_FUNCV( fmtargnumber )
#define SDL_WPRINTF_VARARG_FUNC( fmtargnumber )
#define SDL_WPRINTF_VARARG_FUNCV( fmtargnumber )
#else
#if defined(_MSC_VER) && (_MSC_VER >= 1600)
#include <sal.h>

#define SDL_IN_BYTECAP(x) _In_bytecount_(x)
#define SDL_INOUT_Z_CAP(x) _Inout_z_cap_(x)
#define SDL_OUT_Z_CAP(x) _Out_z_cap_(x)
#define SDL_OUT_CAP(x) _Out_cap_(x)
#define SDL_OUT_BYTECAP(x) _Out_bytecap_(x)
#define SDL_OUT_Z_BYTECAP(x) _Out_z_bytecap_(x)

#define SDL_PRINTF_FORMAT_STRING _Printf_format_string_
#define SDL_SCANF_FORMAT_STRING _Scanf_format_string_impl_
#else
#define SDL_IN_BYTECAP(x)
#define SDL_INOUT_Z_CAP(x)
#define SDL_OUT_Z_CAP(x)
#define SDL_OUT_CAP(x)
#define SDL_OUT_BYTECAP(x)
#define SDL_OUT_Z_BYTECAP(x)
#define SDL_PRINTF_FORMAT_STRING
#define SDL_SCANF_FORMAT_STRING
#endif
#if defined(__GNUC__) || defined(__clang__)
#define SDL_PRINTF_VARARG_FUNC( fmtargnumber ) __attribute__ (( format( __printf__, fmtargnumber, fmtargnumber+1 )))
#define SDL_PRINTF_VARARG_FUNCV( fmtargnumber ) __attribute__(( format( __printf__, fmtargnumber, 0 )))
#define SDL_SCANF_VARARG_FUNC( fmtargnumber ) __attribute__ (( format( __scanf__, fmtargnumber, fmtargnumber+1 )))
#define SDL_SCANF_VARARG_FUNCV( fmtargnumber ) __attribute__(( format( __scanf__, fmtargnumber, 0 )))
#define SDL_WPRINTF_VARARG_FUNC( fmtargnumber )
#define SDL_WPRINTF_VARARG_FUNCV( fmtargnumber )
#else
#define SDL_PRINTF_VARARG_FUNC( fmtargnumber )
#define SDL_PRINTF_VARARG_FUNCV( fmtargnumber )
#define SDL_SCANF_VARARG_FUNC( fmtargnumber )
#define SDL_SCANF_VARARG_FUNCV( fmtargnumber )
#define SDL_WPRINTF_VARARG_FUNC( fmtargnumber )
#define SDL_WPRINTF_VARARG_FUNCV( fmtargnumber )
#endif
#endif

#ifndef DOXYGEN_SHOULD_IGNORE_THIS
SDL_COMPILE_TIME_ASSERT(bool_size, sizeof(bool) == 1);
SDL_COMPILE_TIME_ASSERT(uint8_size, sizeof(Uint8) == 1);
SDL_COMPILE_TIME_ASSERT(sint8_size, sizeof(Sint8) == 1);
SDL_COMPILE_TIME_ASSERT(uint16_size, sizeof(Uint16) == 2);
SDL_COMPILE_TIME_ASSERT(sint16_size, sizeof(Sint16) == 2);
SDL_COMPILE_TIME_ASSERT(uint32_size, sizeof(Uint32) == 4);
SDL_COMPILE_TIME_ASSERT(sint32_size, sizeof(Sint32) == 4);
SDL_COMPILE_TIME_ASSERT(uint64_size, sizeof(Uint64) == 8);
SDL_COMPILE_TIME_ASSERT(sint64_size, sizeof(Sint64) == 8);
#ifndef SDL_NOLONGLONG
SDL_COMPILE_TIME_ASSERT(uint64_longlong, sizeof(Uint64) <= sizeof(unsigned long long));
SDL_COMPILE_TIME_ASSERT(size_t_longlong, sizeof(size_t) <= sizeof(unsigned long long));
#endif
typedef struct SDL_alignment_test
{
    Uint8 a;
    void *b;
} SDL_alignment_test;
SDL_COMPILE_TIME_ASSERT(struct_alignment, sizeof(SDL_alignment_test) == (2 * sizeof(void *)));
SDL_COMPILE_TIME_ASSERT(two_s_complement, SDL_static_cast(int, ~SDL_static_cast(int, 0)) == SDL_static_cast(int, -1));
#endif

#ifndef DOXYGEN_SHOULD_IGNORE_THIS
#if !defined(SDL_PLATFORM_VITA) && !defined(SDL_PLATFORM_3DS)
typedef enum SDL_DUMMY_ENUM
{
    DUMMY_ENUM_VALUE
} SDL_DUMMY_ENUM;

SDL_COMPILE_TIME_ASSERT(enum, sizeof(SDL_DUMMY_ENUM) == sizeof(int));
#endif
#endif

#include <SDL3/SDL_begin_code.h>
#ifdef __cplusplus
extern "C" {
#endif

#define SDL_INIT_INTERFACE(iface)               \
    do {                                        \
        SDL_zerop(iface);                       \
        (iface)->version = sizeof(*(iface));    \
    } while (0)

#ifdef SDL_WIKI_DOCUMENTATION_SECTION

#define SDL_stack_alloc(type, count)    (type*)alloca(sizeof(type)*(count))

#define SDL_stack_free(data) ((void)(data))
#elif !defined(SDL_DISABLE_ALLOCA)
#define SDL_stack_alloc(type, count)    (type*)alloca(sizeof(type)*(count))
#define SDL_stack_free(data)            ((void)(data))
#else
#define SDL_stack_alloc(type, count)    (type*)SDL_malloc(sizeof(type)*(count))
#define SDL_stack_free(data)            SDL_free(data)
#endif

extern SDL_DECLSPEC SDL_MALLOC void * SDLCALL SDL_malloc(size_t size);

extern SDL_DECLSPEC SDL_MALLOC SDL_ALLOC_SIZE2(1, 2) void * SDLCALL SDL_calloc(size_t nmemb, size_t size);

extern SDL_DECLSPEC SDL_ALLOC_SIZE(2) void * SDLCALL SDL_realloc(void *mem, size_t size);

extern SDL_DECLSPEC void SDLCALL SDL_free(void *mem);

typedef void *(SDLCALL *SDL_malloc_func)(size_t size);

typedef void *(SDLCALL *SDL_calloc_func)(size_t nmemb, size_t size);

typedef void *(SDLCALL *SDL_realloc_func)(void *mem, size_t size);

typedef void (SDLCALL *SDL_free_func)(void *mem);

extern SDL_DECLSPEC void SDLCALL SDL_GetOriginalMemoryFunctions(SDL_malloc_func *malloc_func,
                                                            SDL_calloc_func *calloc_func,
                                                            SDL_realloc_func *realloc_func,
                                                            SDL_free_func *free_func);

extern SDL_DECLSPEC void SDLCALL SDL_GetMemoryFunctions(SDL_malloc_func *malloc_func,
                                                    SDL_calloc_func *calloc_func,
                                                    SDL_realloc_func *realloc_func,
                                                    SDL_free_func *free_func);

extern SDL_DECLSPEC bool SDLCALL SDL_SetMemoryFunctions(SDL_malloc_func malloc_func,
                                                            SDL_calloc_func calloc_func,
                                                            SDL_realloc_func realloc_func,
                                                            SDL_free_func free_func);

extern SDL_DECLSPEC SDL_MALLOC void * SDLCALL SDL_aligned_alloc(size_t alignment, size_t size);

extern SDL_DECLSPEC void SDLCALL SDL_aligned_free(void *mem);

extern SDL_DECLSPEC int SDLCALL SDL_GetNumAllocations(void);

typedef struct SDL_Environment SDL_Environment;

extern SDL_DECLSPEC SDL_Environment * SDLCALL SDL_GetEnvironment(void);

extern SDL_DECLSPEC SDL_Environment * SDLCALL SDL_CreateEnvironment(bool populated);

extern SDL_DECLSPEC const char * SDLCALL SDL_GetEnvironmentVariable(SDL_Environment *env, const char *name);

extern SDL_DECLSPEC char ** SDLCALL SDL_GetEnvironmentVariables(SDL_Environment *env);

extern SDL_DECLSPEC bool SDLCALL SDL_SetEnvironmentVariable(SDL_Environment *env, const char *name, const char *value, bool overwrite);

extern SDL_DECLSPEC bool SDLCALL SDL_UnsetEnvironmentVariable(SDL_Environment *env, const char *name);

extern SDL_DECLSPEC void SDLCALL SDL_DestroyEnvironment(SDL_Environment *env);

extern SDL_DECLSPEC const char * SDLCALL SDL_getenv(const char *name);

extern SDL_DECLSPEC const char * SDLCALL SDL_getenv_unsafe(const char *name);

extern SDL_DECLSPEC int SDLCALL SDL_setenv_unsafe(const char *name, const char *value, int overwrite);

extern SDL_DECLSPEC int SDLCALL SDL_unsetenv_unsafe(const char *name);

typedef int (SDLCALL *SDL_CompareCallback)(const void *a, const void *b);

extern SDL_DECLSPEC void SDLCALL SDL_qsort(void *base, size_t nmemb, size_t size, SDL_CompareCallback compare);

extern SDL_DECLSPEC void * SDLCALL SDL_bsearch(const void *key, const void *base, size_t nmemb, size_t size, SDL_CompareCallback compare);

typedef int (SDLCALL *SDL_CompareCallback_r)(void *userdata, const void *a, const void *b);

extern SDL_DECLSPEC void SDLCALL SDL_qsort_r(void *base, size_t nmemb, size_t size, SDL_CompareCallback_r compare, void *userdata);

extern SDL_DECLSPEC void * SDLCALL SDL_bsearch_r(const void *key, const void *base, size_t nmemb, size_t size, SDL_CompareCallback_r compare, void *userdata);

extern SDL_DECLSPEC int SDLCALL SDL_abs(int x);

#define SDL_min(x, y) (((x) < (y)) ? (x) : (y))

#define SDL_max(x, y) (((x) > (y)) ? (x) : (y))

#define SDL_clamp(x, a, b) (((x) < (a)) ? (a) : (((x) > (b)) ? (b) : (x)))

extern SDL_DECLSPEC int SDLCALL SDL_isalpha(int x);

extern SDL_DECLSPEC int SDLCALL SDL_isalnum(int x);

extern SDL_DECLSPEC int SDLCALL SDL_isblank(int x);

extern SDL_DECLSPEC int SDLCALL SDL_iscntrl(int x);

extern SDL_DECLSPEC int SDLCALL SDL_isdigit(int x);

extern SDL_DECLSPEC int SDLCALL SDL_isxdigit(int x);

extern SDL_DECLSPEC int SDLCALL SDL_ispunct(int x);

extern SDL_DECLSPEC int SDLCALL SDL_isspace(int x);

extern SDL_DECLSPEC int SDLCALL SDL_isupper(int x);

extern SDL_DECLSPEC int SDLCALL SDL_islower(int x);

extern SDL_DECLSPEC int SDLCALL SDL_isprint(int x);

extern SDL_DECLSPEC int SDLCALL SDL_isgraph(int x);

extern SDL_DECLSPEC int SDLCALL SDL_toupper(int x);

extern SDL_DECLSPEC int SDLCALL SDL_tolower(int x);

extern SDL_DECLSPEC Uint16 SDLCALL SDL_crc16(Uint16 crc, const void *data, size_t len);

extern SDL_DECLSPEC Uint32 SDLCALL SDL_crc32(Uint32 crc, const void *data, size_t len);

extern SDL_DECLSPEC Uint32 SDLCALL SDL_murmur3_32(const void *data, size_t len, Uint32 seed);

extern SDL_DECLSPEC void * SDLCALL SDL_memcpy(SDL_OUT_BYTECAP(len) void *dst, SDL_IN_BYTECAP(len) const void *src, size_t len);

#ifndef SDL_SLOW_MEMCPY
#ifdef SDL_memcpy
#undef SDL_memcpy
#endif
#define SDL_memcpy  memcpy
#endif

#define SDL_copyp(dst, src)                                                                 \
    { SDL_COMPILE_TIME_ASSERT(SDL_copyp, sizeof (*(dst)) == sizeof (*(src))); }             \
    SDL_memcpy((dst), (src), sizeof(*(src)))

extern SDL_DECLSPEC void * SDLCALL SDL_memmove(SDL_OUT_BYTECAP(len) void *dst, SDL_IN_BYTECAP(len) const void *src, size_t len);

#ifndef SDL_SLOW_MEMMOVE
#ifdef SDL_memmove
#undef SDL_memmove
#endif
#define SDL_memmove memmove
#endif

extern SDL_DECLSPEC void * SDLCALL SDL_memset(SDL_OUT_BYTECAP(len) void *dst, int c, size_t len);

extern SDL_DECLSPEC void * SDLCALL SDL_memset4(void *dst, Uint32 val, size_t dwords);

#ifndef SDL_SLOW_MEMSET
#ifdef SDL_memset
#undef SDL_memset
#endif
#define SDL_memset  memset
#endif

#define SDL_zero(x) SDL_memset(&(x), 0, sizeof((x)))

#define SDL_zerop(x) SDL_memset((x), 0, sizeof(*(x)))

#define SDL_zeroa(x) SDL_memset((x), 0, sizeof((x)))

extern SDL_DECLSPEC int SDLCALL SDL_memcmp(const void *s1, const void *s2, size_t len);

extern SDL_DECLSPEC size_t SDLCALL SDL_wcslen(const wchar_t *wstr);

extern SDL_DECLSPEC size_t SDLCALL SDL_wcsnlen(const wchar_t *wstr, size_t maxlen);

extern SDL_DECLSPEC size_t SDLCALL SDL_wcslcpy(SDL_OUT_Z_CAP(maxlen) wchar_t *dst, const wchar_t *src, size_t maxlen);

extern SDL_DECLSPEC size_t SDLCALL SDL_wcslcat(SDL_INOUT_Z_CAP(maxlen) wchar_t *dst, const wchar_t *src, size_t maxlen);

extern SDL_DECLSPEC wchar_t * SDLCALL SDL_wcsdup(const wchar_t *wstr);

extern SDL_DECLSPEC wchar_t * SDLCALL SDL_wcsstr(const wchar_t *haystack, const wchar_t *needle);

extern SDL_DECLSPEC wchar_t * SDLCALL SDL_wcsnstr(const wchar_t *haystack, const wchar_t *needle, size_t maxlen);

extern SDL_DECLSPEC int SDLCALL SDL_wcscmp(const wchar_t *str1, const wchar_t *str2);

extern SDL_DECLSPEC int SDLCALL SDL_wcsncmp(const wchar_t *str1, const wchar_t *str2, size_t maxlen);

extern SDL_DECLSPEC int SDLCALL SDL_wcscasecmp(const wchar_t *str1, const wchar_t *str2);

extern SDL_DECLSPEC int SDLCALL SDL_wcsncasecmp(const wchar_t *str1, const wchar_t *str2, size_t maxlen);

extern SDL_DECLSPEC long SDLCALL SDL_wcstol(const wchar_t *str, wchar_t **endp, int base);

extern SDL_DECLSPEC size_t SDLCALL SDL_strlen(const char *str);

extern SDL_DECLSPEC size_t SDLCALL SDL_strnlen(const char *str, size_t maxlen);

extern SDL_DECLSPEC size_t SDLCALL SDL_strlcpy(SDL_OUT_Z_CAP(maxlen) char *dst, const char *src, size_t maxlen);

extern SDL_DECLSPEC size_t SDLCALL SDL_utf8strlcpy(SDL_OUT_Z_CAP(dst_bytes) char *dst, const char *src, size_t dst_bytes);

extern SDL_DECLSPEC size_t SDLCALL SDL_strlcat(SDL_INOUT_Z_CAP(maxlen) char *dst, const char *src, size_t maxlen);

extern SDL_DECLSPEC SDL_MALLOC char * SDLCALL SDL_strdup(const char *str);

extern SDL_DECLSPEC SDL_MALLOC char * SDLCALL SDL_strndup(const char *str, size_t maxlen);

extern SDL_DECLSPEC char * SDLCALL SDL_strrev(char *str);

extern SDL_DECLSPEC char * SDLCALL SDL_strupr(char *str);

extern SDL_DECLSPEC char * SDLCALL SDL_strlwr(char *str);

extern SDL_DECLSPEC char * SDLCALL SDL_strchr(const char *str, int c);

extern SDL_DECLSPEC char * SDLCALL SDL_strrchr(const char *str, int c);

extern SDL_DECLSPEC char * SDLCALL SDL_strstr(const char *haystack, const char *needle);

extern SDL_DECLSPEC char * SDLCALL SDL_strnstr(const char *haystack, const char *needle, size_t maxlen);

extern SDL_DECLSPEC char * SDLCALL SDL_strcasestr(const char *haystack, const char *needle);

extern SDL_DECLSPEC char * SDLCALL SDL_strtok_r(char *str, const char *delim, char **saveptr);

extern SDL_DECLSPEC size_t SDLCALL SDL_utf8strlen(const char *str);

extern SDL_DECLSPEC size_t SDLCALL SDL_utf8strnlen(const char *str, size_t bytes);

extern SDL_DECLSPEC char * SDLCALL SDL_itoa(int value, char *str, int radix);

extern SDL_DECLSPEC char * SDLCALL SDL_uitoa(unsigned int value, char *str, int radix);

extern SDL_DECLSPEC char * SDLCALL SDL_ltoa(long value, char *str, int radix);

extern SDL_DECLSPEC char * SDLCALL SDL_ultoa(unsigned long value, char *str, int radix);

#ifndef SDL_NOLONGLONG

extern SDL_DECLSPEC char * SDLCALL SDL_lltoa(long long value, char *str, int radix);

extern SDL_DECLSPEC char * SDLCALL SDL_ulltoa(unsigned long long value, char *str, int radix);
#endif

extern SDL_DECLSPEC int SDLCALL SDL_atoi(const char *str);

extern SDL_DECLSPEC double SDLCALL SDL_atof(const char *str);

extern SDL_DECLSPEC long SDLCALL SDL_strtol(const char *str, char **endp, int base);

extern SDL_DECLSPEC unsigned long SDLCALL SDL_strtoul(const char *str, char **endp, int base);

#ifndef SDL_NOLONGLONG

extern SDL_DECLSPEC long long SDLCALL SDL_strtoll(const char *str, char **endp, int base);

extern SDL_DECLSPEC unsigned long long SDLCALL SDL_strtoull(const char *str, char **endp, int base);
#endif

extern SDL_DECLSPEC double SDLCALL SDL_strtod(const char *str, char **endp);

extern SDL_DECLSPEC int SDLCALL SDL_strcmp(const char *str1, const char *str2);

extern SDL_DECLSPEC int SDLCALL SDL_strncmp(const char *str1, const char *str2, size_t maxlen);

extern SDL_DECLSPEC int SDLCALL SDL_strcasecmp(const char *str1, const char *str2);

extern SDL_DECLSPEC int SDLCALL SDL_strncasecmp(const char *str1, const char *str2, size_t maxlen);

extern SDL_DECLSPEC char * SDLCALL SDL_strpbrk(const char *str, const char *breakset);

#define SDL_INVALID_UNICODE_CODEPOINT 0xFFFD

extern SDL_DECLSPEC Uint32 SDLCALL SDL_StepUTF8(const char **pstr, size_t *pslen);

extern SDL_DECLSPEC Uint32 SDLCALL SDL_StepBackUTF8(const char *start, const char **pstr);

extern SDL_DECLSPEC char * SDLCALL SDL_UCS4ToUTF8(Uint32 codepoint, char *dst);

extern SDL_DECLSPEC int SDLCALL SDL_sscanf(const char *text, SDL_SCANF_FORMAT_STRING const char *fmt, ...) SDL_SCANF_VARARG_FUNC(2);

extern SDL_DECLSPEC int SDLCALL SDL_vsscanf(const char *text, SDL_SCANF_FORMAT_STRING const char *fmt, va_list ap) SDL_SCANF_VARARG_FUNCV(2);

extern SDL_DECLSPEC int SDLCALL SDL_snprintf(SDL_OUT_Z_CAP(maxlen) char *text, size_t maxlen, SDL_PRINTF_FORMAT_STRING const char *fmt, ...) SDL_PRINTF_VARARG_FUNC(3);

extern SDL_DECLSPEC int SDLCALL SDL_swprintf(SDL_OUT_Z_CAP(maxlen) wchar_t *text, size_t maxlen, SDL_PRINTF_FORMAT_STRING const wchar_t *fmt, ...) SDL_WPRINTF_VARARG_FUNC(3);

extern SDL_DECLSPEC int SDLCALL SDL_vsnprintf(SDL_OUT_Z_CAP(maxlen) char *text, size_t maxlen, SDL_PRINTF_FORMAT_STRING const char *fmt, va_list ap) SDL_PRINTF_VARARG_FUNCV(3);

extern SDL_DECLSPEC int SDLCALL SDL_vswprintf(SDL_OUT_Z_CAP(maxlen) wchar_t *text, size_t maxlen, SDL_PRINTF_FORMAT_STRING const wchar_t *fmt, va_list ap) SDL_WPRINTF_VARARG_FUNCV(3);

extern SDL_DECLSPEC int SDLCALL SDL_asprintf(char **strp, SDL_PRINTF_FORMAT_STRING const char *fmt, ...) SDL_PRINTF_VARARG_FUNC(2);

extern SDL_DECLSPEC int SDLCALL SDL_vasprintf(char **strp, SDL_PRINTF_FORMAT_STRING const char *fmt, va_list ap) SDL_PRINTF_VARARG_FUNCV(2);

extern SDL_DECLSPEC void SDLCALL SDL_srand(Uint64 seed);

extern SDL_DECLSPEC Sint32 SDLCALL SDL_rand(Sint32 n);

extern SDL_DECLSPEC float SDLCALL SDL_randf(void);

extern SDL_DECLSPEC Uint32 SDLCALL SDL_rand_bits(void);

extern SDL_DECLSPEC Sint32 SDLCALL SDL_rand_r(Uint64 *state, Sint32 n);

extern SDL_DECLSPEC float SDLCALL SDL_randf_r(Uint64 *state);

extern SDL_DECLSPEC Uint32 SDLCALL SDL_rand_bits_r(Uint64 *state);

#ifndef SDL_PI_D

#define SDL_PI_D   3.141592653589793238462643383279502884
#endif

#ifndef SDL_PI_F

#define SDL_PI_F   3.141592653589793238462643383279502884F
#endif

extern SDL_DECLSPEC double SDLCALL SDL_acos(double x);

extern SDL_DECLSPEC float SDLCALL SDL_acosf(float x);

extern SDL_DECLSPEC double SDLCALL SDL_asin(double x);

extern SDL_DECLSPEC float SDLCALL SDL_asinf(float x);

extern SDL_DECLSPEC double SDLCALL SDL_atan(double x);

extern SDL_DECLSPEC float SDLCALL SDL_atanf(float x);

extern SDL_DECLSPEC double SDLCALL SDL_atan2(double y, double x);

extern SDL_DECLSPEC float SDLCALL SDL_atan2f(float y, float x);

extern SDL_DECLSPEC double SDLCALL SDL_ceil(double x);

extern SDL_DECLSPEC float SDLCALL SDL_ceilf(float x);

extern SDL_DECLSPEC double SDLCALL SDL_copysign(double x, double y);

extern SDL_DECLSPEC float SDLCALL SDL_copysignf(float x, float y);

extern SDL_DECLSPEC double SDLCALL SDL_cos(double x);

extern SDL_DECLSPEC float SDLCALL SDL_cosf(float x);

extern SDL_DECLSPEC double SDLCALL SDL_exp(double x);

extern SDL_DECLSPEC float SDLCALL SDL_expf(float x);

extern SDL_DECLSPEC double SDLCALL SDL_fabs(double x);

extern SDL_DECLSPEC float SDLCALL SDL_fabsf(float x);

extern SDL_DECLSPEC double SDLCALL SDL_floor(double x);

extern SDL_DECLSPEC float SDLCALL SDL_floorf(float x);

extern SDL_DECLSPEC double SDLCALL SDL_trunc(double x);

extern SDL_DECLSPEC float SDLCALL SDL_truncf(float x);

extern SDL_DECLSPEC double SDLCALL SDL_fmod(double x, double y);

extern SDL_DECLSPEC float SDLCALL SDL_fmodf(float x, float y);

extern SDL_DECLSPEC int SDLCALL SDL_isinf(double x);

extern SDL_DECLSPEC int SDLCALL SDL_isinff(float x);

extern SDL_DECLSPEC int SDLCALL SDL_isnan(double x);

extern SDL_DECLSPEC int SDLCALL SDL_isnanf(float x);

extern SDL_DECLSPEC double SDLCALL SDL_log(double x);

extern SDL_DECLSPEC float SDLCALL SDL_logf(float x);

extern SDL_DECLSPEC double SDLCALL SDL_log10(double x);

extern SDL_DECLSPEC float SDLCALL SDL_log10f(float x);

extern SDL_DECLSPEC double SDLCALL SDL_modf(double x, double *y);

extern SDL_DECLSPEC float SDLCALL SDL_modff(float x, float *y);

extern SDL_DECLSPEC double SDLCALL SDL_pow(double x, double y);

extern SDL_DECLSPEC float SDLCALL SDL_powf(float x, float y);

extern SDL_DECLSPEC double SDLCALL SDL_round(double x);

extern SDL_DECLSPEC float SDLCALL SDL_roundf(float x);

extern SDL_DECLSPEC long SDLCALL SDL_lround(double x);

extern SDL_DECLSPEC long SDLCALL SDL_lroundf(float x);

extern SDL_DECLSPEC double SDLCALL SDL_scalbn(double x, int n);

extern SDL_DECLSPEC float SDLCALL SDL_scalbnf(float x, int n);

extern SDL_DECLSPEC double SDLCALL SDL_sin(double x);

extern SDL_DECLSPEC float SDLCALL SDL_sinf(float x);

extern SDL_DECLSPEC double SDLCALL SDL_sqrt(double x);

extern SDL_DECLSPEC float SDLCALL SDL_sqrtf(float x);

extern SDL_DECLSPEC double SDLCALL SDL_tan(double x);

extern SDL_DECLSPEC float SDLCALL SDL_tanf(float x);

typedef struct SDL_iconv_data_t *SDL_iconv_t;

extern SDL_DECLSPEC SDL_iconv_t SDLCALL SDL_iconv_open(const char *tocode,
                                                   const char *fromcode);

extern SDL_DECLSPEC int SDLCALL SDL_iconv_close(SDL_iconv_t cd);

extern SDL_DECLSPEC size_t SDLCALL SDL_iconv(SDL_iconv_t cd, const char **inbuf,
                                         size_t *inbytesleft, char **outbuf,
                                         size_t *outbytesleft);

#define SDL_ICONV_ERROR     (size_t)-1
#define SDL_ICONV_E2BIG     (size_t)-2
#define SDL_ICONV_EILSEQ    (size_t)-3
#define SDL_ICONV_EINVAL    (size_t)-4

extern SDL_DECLSPEC char * SDLCALL SDL_iconv_string(const char *tocode,
                                               const char *fromcode,
                                               const char *inbuf,
                                               size_t inbytesleft);

#define SDL_iconv_utf8_locale(S)    SDL_iconv_string("", "UTF-8", S, SDL_strlen(S)+1)

#define SDL_iconv_utf8_ucs2(S)      SDL_reinterpret_cast(Uint16 *, SDL_iconv_string("UCS-2", "UTF-8", S, SDL_strlen(S)+1))

#define SDL_iconv_utf8_ucs4(S)      SDL_reinterpret_cast(Uint32 *, SDL_iconv_string("UCS-4", "UTF-8", S, SDL_strlen(S)+1))

#define SDL_iconv_wchar_utf8(S)     SDL_iconv_string("UTF-8", "WCHAR_T", SDL_reinterpret_cast(const char *, S), (SDL_wcslen(S)+1)*sizeof(wchar_t))

#if defined(__clang_analyzer__) && !defined(SDL_DISABLE_ANALYZE_MACROS)

#if !defined(HAVE_STRLCPY) && !defined(strlcpy)
size_t strlcpy(char *dst, const char *src, size_t size);
#endif

#if !defined(HAVE_STRLCAT) && !defined(strlcat)
size_t strlcat(char *dst, const char *src, size_t size);
#endif

#if !defined(HAVE_WCSLCPY) && !defined(wcslcpy)
size_t wcslcpy(wchar_t *dst, const wchar_t *src, size_t size);
#endif

#if !defined(HAVE_WCSLCAT) && !defined(wcslcat)
size_t wcslcat(wchar_t *dst, const wchar_t *src, size_t size);
#endif

#if !defined(HAVE_STRTOK_R) && !defined(strtok_r)
char *strtok_r(char *str, const char *delim, char **saveptr);
#endif

#ifndef _WIN32
char *strdup(const char *str);
#endif

#include <stdio.h>
#include <stdlib.h>

#define SDL_malloc malloc
#define SDL_calloc calloc
#define SDL_realloc realloc
#define SDL_free free
#ifndef SDL_memcpy
#define SDL_memcpy memcpy
#endif
#ifndef SDL_memmove
#define SDL_memmove memmove
#endif
#ifndef SDL_memset
#define SDL_memset memset
#endif
#define SDL_memcmp memcmp
#define SDL_strlcpy strlcpy
#define SDL_strlcat strlcat
#define SDL_strlen strlen
#define SDL_wcslen wcslen
#define SDL_wcslcpy wcslcpy
#define SDL_wcslcat wcslcat
#define SDL_strdup strdup
#define SDL_wcsdup wcsdup
#define SDL_strchr strchr
#define SDL_strrchr strrchr
#define SDL_strstr strstr
#define SDL_wcsstr wcsstr
#define SDL_strtok_r strtok_r
#define SDL_strcmp strcmp
#define SDL_wcscmp wcscmp
#define SDL_strncmp strncmp
#define SDL_wcsncmp wcsncmp
#define SDL_strcasecmp strcasecmp
#define SDL_strncasecmp strncasecmp
#define SDL_strpbrk strpbrk
#define SDL_sscanf sscanf
#define SDL_vsscanf vsscanf
#define SDL_snprintf snprintf
#define SDL_vsnprintf vsnprintf
#endif

SDL_FORCE_INLINE bool SDL_size_mul_check_overflow(size_t a, size_t b, size_t *ret)
{
    if (a != 0 && b > SDL_SIZE_MAX / a) {
        return false;
    }
    *ret = a * b;
    return true;
}

#ifndef SDL_WIKI_DOCUMENTATION_SECTION
#if SDL_HAS_BUILTIN(__builtin_mul_overflow)
SDL_FORCE_INLINE bool SDL_size_mul_check_overflow_builtin(size_t a, size_t b, size_t *ret)
{
    return (__builtin_mul_overflow(a, b, ret) == 0);
}
#define SDL_size_mul_check_overflow(a, b, ret) SDL_size_mul_check_overflow_builtin(a, b, ret)
#endif
#endif

SDL_FORCE_INLINE bool SDL_size_add_check_overflow(size_t a, size_t b, size_t *ret)
{
    if (b > SDL_SIZE_MAX - a) {
        return false;
    }
    *ret = a + b;
    return true;
}

#ifndef SDL_WIKI_DOCUMENTATION_SECTION
#if SDL_HAS_BUILTIN(__builtin_add_overflow)
SDL_FORCE_INLINE bool SDL_size_add_check_overflow_builtin(size_t a, size_t b, size_t *ret)
{
    return (__builtin_add_overflow(a, b, ret) == 0);
}
#define SDL_size_add_check_overflow(a, b, ret) SDL_size_add_check_overflow_builtin(a, b, ret)
#endif
#endif

#ifdef SDL_WIKI_DOCUMENTATION_SECTION

typedef void (*SDL_FunctionPointer)(void);
#elif defined(SDL_FUNCTION_POINTER_IS_VOID_POINTER)
typedef void *SDL_FunctionPointer;
#else
typedef void (*SDL_FunctionPointer)(void);
#endif

#ifdef __cplusplus
}
#endif
#include <SDL3/SDL_close_code.h>

#endif
