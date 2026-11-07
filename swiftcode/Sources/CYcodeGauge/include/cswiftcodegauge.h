#ifndef CSWIFTCODEGAUGE_H
#define CSWIFTCODEGAUGE_H
#include <stddef.h>
#include <stdint.h>

int ycg_spawn_held(const char *path, char *const argv[], char *const envp[], int *gate);
int ycg_release(int gate);
int ycg_wait(int pid, int nohang, int *exitStatus);

int ycg_perf_paranoid(void);

typedef struct ycg_perf {
    int fd;
    void *base;
    size_t size;
    size_t dataSize;
    uint64_t lost;
} ycg_perf;

int ycg_perf_open(ycg_perf *p, int tid, int cpu, uint64_t periodNs, int inheritOnExec, int kernel, int ringPages);
int ycg_cpu_count(void);
size_t ycg_perf_read(ycg_perf *p, uint64_t *out, size_t capacity);
void ycg_perf_close(ycg_perf *p);

int ycg_threads(int pid, int *out, int capacity);
#endif
