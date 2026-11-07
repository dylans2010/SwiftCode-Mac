#ifndef CKVM_SNAPSHOT_H
#define CKVM_SNAPSHOT_H

#include <stddef.h>
#include <stdint.h>

#if defined(__linux__) && defined(__aarch64__)

int ckvm_get_one_reg_bytes(int vcpu_fd, uint64_t reg_id, void *buffer);
int ckvm_set_one_reg_bytes(int vcpu_fd, uint64_t reg_id, const void *buffer);

uint64_t ckvm_reg_fp_v(unsigned n);
uint64_t ckvm_reg_fpsr(void);
uint64_t ckvm_reg_fpcr(void);

enum { CKVM_FP_STATE_SIZE = 32 * 16 + 8 };
int ckvm_get_fp_state(int vcpu_fd, uint8_t *out);
int ckvm_set_fp_state(int vcpu_fd, const uint8_t *in);

int ckvm_kick_tid(long tid, int signo);

int ckvm_mincore(const void *address, size_t size, uint8_t *vec);

long ckvm_pagemap(const void *address, size_t count, uint64_t *out);

int ckvm_map_overlay(void *address, size_t size, int fd, uint64_t offset);

int ckvm_reset_anonymous(void *address, size_t size);

int ckvm_prefetch_file(int fd, uint64_t offset, uint64_t length);

#endif
#endif
