#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    int i = 1;
    for (; i + 1 < argc && strcmp(argv[i], "-l") == 0; i += 2) {
        if (!dlopen(argv[i + 1], RTLD_LAZY)) fprintf(stderr, "symaddr: dlopen %s: %s\n", argv[i + 1], dlerror());
    }
    if (i + 1 >= argc) {
        fprintf(stderr, "usage: symaddr [-l image]... <in> <out>\n");
        return 64;
    }
    FILE *in = fopen(argv[i], "r"), *out = fopen(argv[i + 1], "w");
    if (!in || !out) {
        perror("symaddr");
        return 1;
    }
    unsigned long long a;
    while (fscanf(in, "%llx", &a) == 1) {
        Dl_info info;
        if (a && dladdr((void *)(uintptr_t)a, &info) && info.dli_fname) {
            const char *base = strrchr(info.dli_fname, '/');
            fprintf(out, "%llx %s+0x%llx %s+%lld\n", a, base ? base + 1 : info.dli_fname,
                    a - (unsigned long long)(uintptr_t)info.dli_fbase, info.dli_sname ? info.dli_sname : "?",
                    info.dli_saddr ? (long long)(a - (unsigned long long)(uintptr_t)info.dli_saddr) : 0LL);
        } else {
            fprintf(out, "%llx ?\n", a);
        }
    }
    fclose(out);
    return 0;
}
