#ifndef CKVM_CPUFEAT_H
#define CKVM_CPUFEAT_H

#include <stdint.h>

#if defined(__linux__) && defined(__aarch64__)

int ckvm_probe_vcpu_registers(const uint64_t *ids, uint64_t *values, int32_t *results, int count);

uint64_t ckvm_host_ctr_el0(void);
uint64_t ckvm_host_dczid_el0(void);
uint64_t ckvm_host_fpcr_trap_probe(void);

#endif
#endif
