#include "yc_platform.h"

typedef yc_u64 __attribute__((may_alias, aligned(1))) yc_unaligned_u64;
typedef yc_u64 __attribute__((may_alias)) yc_word;

#define WORD sizeof(yc_word)
#define ONES 0x0101010101010101ull
#define HIGHS 0x8080808080808080ull
#define HAS_ZERO(w) (((w) - ONES) & ~(w) & HIGHS)

typedef unsigned char yc_v16 __attribute__((vector_size(16), aligned(1), may_alias));
typedef yc_u32 __attribute__((may_alias, aligned(1))) yc_unaligned_u32;
typedef yc_u16 __attribute__((may_alias, aligned(1))) yc_unaligned_u16;

#define LD16(p) (*(const yc_v16 *)(const void *)(p))
#define ST16(p, v) (*(yc_v16 *)(void *)(p) = (v))
#define LD8(p) (*(const yc_unaligned_u64 *)(const void *)(p))
#define ST8(p, v) (*(yc_unaligned_u64 *)(void *)(p) = (v))

static inline void copy_upto32(unsigned char *d, const unsigned char *s, yc_size_t n)
{
    if (n >= 16) {
        yc_v16 a = LD16(s), b = LD16(s + n - 16);
        ST16(d, a);
        ST16(d + n - 16, b);
    } else if (n >= 8) {
        yc_u64 a = LD8(s), b = LD8(s + n - 8);
        ST8(d, a);
        ST8(d + n - 8, b);
    } else if (n >= 4) {
        yc_u32 a = *(const yc_unaligned_u32 *)(const void *)s;
        yc_u32 b = *(const yc_unaligned_u32 *)(const void *)(s + n - 4);
        *(yc_unaligned_u32 *)(void *)d = a;
        *(yc_unaligned_u32 *)(void *)(d + n - 4) = b;
    } else if (n >= 2) {
        yc_u16 a = *(const yc_unaligned_u16 *)(const void *)s;
        yc_u16 b = *(const yc_unaligned_u16 *)(const void *)(s + n - 2);
        *(yc_unaligned_u16 *)(void *)d = a;
        *(yc_unaligned_u16 *)(void *)(d + n - 2) = b;
    } else if (n == 1) {
        *d = *s;
    }
}

YC_EXPORT void *YC_FN(_platform_memmove)(void *dst, const void *src, yc_size_t n)
{
    unsigned char *d = dst;
    const unsigned char *s = src;
    if (d == s || n == 0)
        return dst;
    if (n <= 32) {
        copy_upto32(d, s, n);
        return dst;
    }
    if ((yc_uintptr_t)d - (yc_uintptr_t)s >= n) {
        yc_v16 head = LD16(s), tail = LD16(s + n - 16);
        unsigned char *base = d, *end = d + n;
        yc_size_t k = 16 - ((yc_uintptr_t)d & 15);
        d += k;
        s += k;
        n -= k;
        while (n > 64) {
            yc_v16 a = LD16(s), b = LD16(s + 16), c = LD16(s + 32), e = LD16(s + 48);
            ST16(d, a);
            ST16(d + 16, b);
            ST16(d + 32, c);
            ST16(d + 48, e);
            d += 64;
            s += 64;
            n -= 64;
        }
        while (n > 16) {
            ST16(d, LD16(s));
            d += 16;
            s += 16;
            n -= 16;
        }
        ST16(end - 16, tail);
        ST16(base, head);
    } else {
        yc_v16 head = LD16(s), tail = LD16(s + n - 16);
        unsigned char *base = d, *end = d + n;
        yc_size_t k = (yc_uintptr_t)(d + n) & 15;
        if (k == 0)
            k = 16;
        n -= k;
        while (n > 64) {
            yc_v16 a = LD16(s + n - 16), b = LD16(s + n - 32), c = LD16(s + n - 48), e = LD16(s + n - 64);
            ST16(d + n - 16, a);
            ST16(d + n - 32, b);
            ST16(d + n - 48, c);
            ST16(d + n - 64, e);
            n -= 64;
        }
        while (n > 16) {
            ST16(d + n - 16, LD16(s + n - 16));
            n -= 16;
        }
        ST16(end - 16, tail);
        ST16(base, head);
    }
    return dst;
}

YC_EXPORT void *YC_FN(_platform_memccpy)(void *dst, const void *src, int c, yc_size_t n)
{
    unsigned char *d = dst;
    const unsigned char *s = src;
    unsigned char ch = (unsigned char)c;
    while (n--) {
        unsigned char v = *s++;
        *d++ = v;
        if (v == ch)
            return d;
    }
    return YC_NULL;
}

YC_EXPORT void *YC_FN(_platform_memchr)(const void *p, int c, yc_size_t n)
{
    const unsigned char *s = p;
    unsigned char ch = (unsigned char)c;
    while (n && ((yc_uintptr_t)s & (WORD - 1))) {
        if (*s == ch)
            return (void *)s;
        s++;
        n--;
    }
    yc_u64 pattern = (yc_u64)ch * ONES;
    while (n >= WORD) {
        yc_u64 w = *(const yc_word *)s ^ pattern;
        if (HAS_ZERO(w))
            break;
        s += WORD;
        n -= WORD;
    }
    for (; n; n--, s++)
        if (*s == ch)
            return (void *)s;
    return YC_NULL;
}

YC_EXPORT int YC_FN(_platform_memcmp)(const void *a, const void *b, yc_size_t n)
{
    const unsigned char *x = a, *y = b;
    while (n >= WORD && *(const yc_unaligned_u64 *)x == *(const yc_unaligned_u64 *)y) {
        x += WORD;
        y += WORD;
        n -= WORD;
    }
    for (; n; n--, x++, y++)
        if (*x != *y)
            return (int)*x - (int)*y;
    return 0;
}

YC_EXPORT int YC_FN(_platform_memcmp_zero_aligned8)(const void *p, yc_size_t n)
{
    const unsigned char *s = p;
    while (n >= WORD) {
        if (*(const yc_unaligned_u64 *)s != 0)
            return 1;
        s += WORD;
        n -= WORD;
    }
    for (; n; n--, s++)
        if (*s)
            return 1;
    return 0;
}

static inline void fill16(unsigned char *d, yc_v16 v, yc_size_t n)
{
    if (n < 16) {
        for (yc_size_t i = 0; i < n; i++)
            d[i] = v[i];
        return;
    }
    unsigned char *end = d + n;
    yc_v16 tail = v;
    yc_size_t shift = (n - 16) & 15;
    if (shift)
        for (int i = 0; i < 16; i++)
            tail[i] = v[(i + shift) & 15];
    while (n >= 64) {
        ST16(d, v);
        ST16(d + 16, v);
        ST16(d + 32, v);
        ST16(d + 48, v);
        d += 64;
        n -= 64;
    }
    while (n >= 16) {
        ST16(d, v);
        d += 16;
        n -= 16;
    }
    ST16(end - 16, tail);
}

static inline yc_v16 splat16(unsigned char b)
{
    yc_v16 v;
    for (int i = 0; i < 16; i++)
        v[i] = b;
    return v;
}

YC_EXPORT void *YC_FN(_platform_memset)(void *dst, int c, yc_size_t n)
{
    unsigned char *d = dst;
    if (n <= 32) {
        unsigned char b = (unsigned char)c;
        if (n >= 16) {
            ST16(d, splat16(b));
            ST16(d + n - 16, splat16(b));
        } else if (n >= 8) {
            yc_u64 w = (yc_u64)b * ONES;
            ST8(d, w);
            ST8(d + n - 8, w);
        } else {
            for (yc_size_t i = 0; i < n; i++)
                d[i] = b;
        }
        return dst;
    }
    fill16(d, splat16((unsigned char)c), n);
    return dst;
}

static void zero_bytes(unsigned char *d, yc_size_t n)
{
#if defined(__aarch64__)
    if (n >= 512) {
        yc_u64 dczid;
        __asm__ volatile("mrs %0, dczid_el0" : "=r"(dczid));
        if (!(dczid & 16)) {
            yc_size_t block = (yc_size_t)4 << (dczid & 15);
            if (block >= 16 && block <= 2048 && n >= 2 * block) {
                unsigned char *end = d + n;
                unsigned char *a = (unsigned char *)(((yc_uintptr_t)d + block - 1) & ~(yc_uintptr_t)(block - 1));
                unsigned char *b = (unsigned char *)((yc_uintptr_t)end & ~(yc_uintptr_t)(block - 1));
                fill16(d, splat16(0), (yc_size_t)(a - d));
                for (unsigned char *q = a; q < b; q += block)
                    __asm__ volatile("dc zva, %0" : : "r"(q) : "memory");
                fill16(b, splat16(0), (yc_size_t)(end - b));
                return;
            }
        }
    }
#endif
    YC_FN(_platform_memset)(d, 0, n);
}

YC_EXPORT void YC_FN(_platform_bzero)(void *dst, yc_size_t n)
{
    zero_bytes(dst, n);
}

YC_EXPORT void YC_FN(__bzero)(void *dst, yc_size_t n)
{
    zero_bytes(dst, n);
}

static void fill_pattern(unsigned char *d, const unsigned char *pat, yc_size_t plen, yc_size_t len)
{
    yc_v16 v;
    for (int i = 0; i < 16; i++)
        v[i] = pat[(yc_size_t)i % plen];
    fill16(d, v, len);
}

YC_EXPORT void YC_FN(_platform_memset_pattern4)(void *dst, const void *pattern, yc_size_t len)
{
    fill_pattern(dst, pattern, 4, len);
}

YC_EXPORT void YC_FN(_platform_memset_pattern8)(void *dst, const void *pattern, yc_size_t len)
{
    fill_pattern(dst, pattern, 8, len);
}

YC_EXPORT void YC_FN(_platform_memset_pattern16)(void *dst, const void *pattern, yc_size_t len)
{
    fill_pattern(dst, pattern, 16, len);
}

YC_HIDDEN yc_size_t __yc_strlen(const char *str)
{
    const char *s = str;
    while ((yc_uintptr_t)s & (WORD - 1)) {
        if (*s == 0)
            return (yc_size_t)(s - str);
        s++;
    }
    for (;;) {
        yc_word w = *(const yc_word *)s;
        if (HAS_ZERO(w))
            break;
        s += WORD;
    }
    while (*s)
        s++;
    return (yc_size_t)(s - str);
}

YC_EXPORT yc_size_t YC_FN(_platform_strlen)(const char *s)
{
    return __yc_strlen(s);
}

YC_EXPORT yc_size_t YC_FN(_platform_strnlen)(const char *s, yc_size_t max)
{
    yc_size_t n = 0;
    while (n < max && ((yc_uintptr_t)(s + n) & (WORD - 1))) {
        if (s[n] == 0)
            return n;
        n++;
    }
    while (max - n >= WORD && !HAS_ZERO(*(const yc_word *)(const void *)(s + n)))
        n += WORD;
    while (n < max && s[n])
        n++;
    return n;
}

YC_EXPORT char *YC_FN(_platform_strchr)(const char *s, int c)
{
    char ch = (char)c;
    for (;; s++) {
        if (*s == ch)
            return (char *)s;
        if (*s == 0)
            return YC_NULL;
    }
}

#define IN_PAGE8(p) (((yc_uintptr_t)(p) & 4095) <= 4096 - WORD)

YC_EXPORT int YC_FN(_platform_strcmp)(const char *a, const char *b)
{
    const unsigned char *x = (const unsigned char *)a, *y = (const unsigned char *)b;
    for (;;) {
        if (YC_LIKELY(IN_PAGE8(x) && IN_PAGE8(y))) {
            yc_u64 u = LD8(x), v = LD8(y);
            if (u == v && !HAS_ZERO(u)) {
                x += WORD;
                y += WORD;
                continue;
            }
            for (int i = 0; i < (int)WORD; i++, x++, y++)
                if (*x != *y || *x == 0)
                    return (int)*x - (int)*y;
        }
        if (*x != *y || *x == 0)
            return (int)*x - (int)*y;
        x++;
        y++;
    }
}

YC_EXPORT int YC_FN(_platform_strncmp)(const char *a, const char *b, yc_size_t n)
{
    const unsigned char *x = (const unsigned char *)a, *y = (const unsigned char *)b;
    for (; n; n--, x++, y++) {
        if (*x != *y)
            return (int)*x - (int)*y;
        if (*x == 0)
            return 0;
    }
    return 0;
}

YC_EXPORT char *YC_FN(_platform_strcpy)(char *dst, const char *src)
{
    char *d = dst;
    while ((*d++ = *src++) != 0) {
    }
    return dst;
}

YC_EXPORT char *YC_FN(_platform_strncpy)(char *dst, const char *src, yc_size_t n)
{
    char *d = dst;
    while (n && *src) {
        *d++ = *src++;
        n--;
    }
    while (n--)
        *d++ = 0;
    return dst;
}

YC_EXPORT yc_size_t YC_FN(_platform_strlcpy)(char *dst, const char *src, yc_size_t size)
{
    yc_size_t len = __yc_strlen(src);
    if (size) {
        yc_size_t n = len < size - 1 ? len : size - 1;
        YC_FN(_platform_memmove)(dst, src, n);
        dst[n] = 0;
    }
    return len;
}

YC_EXPORT yc_size_t YC_FN(_platform_strlcat)(char *dst, const char *src, yc_size_t size)
{
    yc_size_t dlen = YC_FN(_platform_strnlen)(dst, size);
    yc_size_t slen = __yc_strlen(src);
    if (dlen == size)
        return size + slen;
    yc_size_t room = size - dlen - 1;
    yc_size_t n = slen < room ? slen : room;
    YC_FN(_platform_memmove)(dst + dlen, src, n);
    dst[dlen + n] = 0;
    return dlen + slen;
}

YC_EXPORT char *YC_FN(_platform_strstr)(const char *hay, const char *needle)
{
    if (*needle == 0)
        return (char *)hay;
    yc_size_t nlen = __yc_strlen(needle);
    for (; *hay; hay++) {
        if (*hay == *needle && YC_FN(_platform_strncmp)(hay, needle, nlen) == 0)
            return (char *)hay;
    }
    return YC_NULL;
}
