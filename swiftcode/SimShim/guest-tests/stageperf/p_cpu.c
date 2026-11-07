#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifndef HOST_BUILD
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#endif

static double now_ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec * 1e9 + (double)t.tv_nsec;
}

static uint64_t rng = 88172645463325252ull;
static uint64_t next(void)
{
    rng ^= rng << 13;
    rng ^= rng >> 7;
    rng ^= rng << 17;
    return rng;
}

static void **make_chain(size_t n, size_t stride, char **base)
{
    char *mem = malloc(n * stride + 64);
    size_t *order = malloc(n * sizeof(size_t));
    for (size_t i = 0; i < n; i++) order[i] = i;
    for (size_t i = n - 1; i > 0; i--) {
        size_t j = next() % (i + 1);
        size_t t = order[i]; order[i] = order[j]; order[j] = t;
    }
    for (size_t i = 0; i < n; i++) {
        void **slot = (void **)(mem + order[i] * stride);
        *slot = mem + order[(i + 1) % n] * stride;
    }
    void **start = (void **)(mem + order[0] * stride);
    free(order);
    *base = mem;
    return start;
}

static double chase(size_t n, size_t stride, size_t hops)
{
    char *base;
    void **p = make_chain(n, stride, &base);
    for (size_t i = 0; i < n; i++) p = (void **)*p;
    double t0 = now_ns();
    for (size_t i = 0; i < hops; i++) p = (void **)*p;
    double t = (now_ns() - t0) / (double)hops;
    if (p == NULL) printf("x");
    free(base);
    return t;
}

int main(void)
{
    const long iters = 200000000;
    double t0 = now_ns();
    uint64_t x = 1;
    for (long i = 0; i < iters; i++) { x ^= x << 13; x ^= x >> 7; x ^= x << 17; }
    double alu = (now_ns() - t0) / (double)iters;
    if (x == 0) printf("x");

    double pages = chase(16384, 16384, 20000000);
    double lines = chase(1280, 16384 + 64, 20000000);

    double headers = 0;
    unsigned images = 0;
#ifndef HOST_BUILD
    images = _dyld_image_count();
    const long rounds = 2000;
    uint64_t sum = 0;
    t0 = now_ns();
    for (long r = 0; r < rounds; r++) {
        for (unsigned i = 0; i < images; i++) {
            const struct mach_header_64 *mh = (const struct mach_header_64 *)_dyld_get_image_header(i);
            if (!mh) continue;
            const struct load_command *lc = (const struct load_command *)(mh + 1);
            for (uint32_t c = 0; c < mh->ncmds; c++) {
                if (lc->cmd == LC_ID_DYLIB) {
                    const struct dylib_command *d = (const struct dylib_command *)lc;
                    sum += strlen((const char *)lc + d->dylib.name.offset);
                    break;
                }
                sum += lc->cmdsize;
                lc = (const struct load_command *)((const char *)lc + lc->cmdsize);
            }
        }
    }
    headers = (now_ns() - t0) / (double)(rounds * (images ? images : 1));
    if (sum == 0) printf("x");
#endif
    printf("cpu alu=%.3f ns chase=%.1f ns lines=%.1f ns headers=%.1f ns images=%u\n", alu, pages, lines, headers, images);
    return 0;
}
