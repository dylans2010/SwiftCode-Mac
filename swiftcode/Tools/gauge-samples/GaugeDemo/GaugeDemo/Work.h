#ifndef GAUGEDEMO_WORK_H
#define GAUGEDEMO_WORK_H
#include <stdint.h>

double gauge_demo_round(int round, uint64_t *checksum);

uint64_t gauge_demo_background(int round);

void gauge_demo_tick(int round);
#endif
