#ifndef CKVM_H
#define CKVM_H

#include <stddef.h>
#include <stdint.h>

int ckvm_available(void);

#if defined(__linux__) && defined(__aarch64__)

int ckvm_open(void);
int ckvm_close(int fd);
int ckvm_get_api_version(int kvm_fd);
int ckvm_check_extension(int kvm_fd, long extension);
int ckvm_create_vm(int kvm_fd, unsigned long machine_type);
int ckvm_set_user_memory_region(int vm_fd, uint32_t slot, uint32_t flags,
                                uint64_t guest_phys_addr, uint64_t memory_size,
                                uint64_t userspace_addr);

void *ckvm_alloc_anonymous(size_t size);
void *ckvm_alloc_anonymous_aligned(size_t size, size_t alignment, int huge);
int ckvm_free_anonymous(void *address, size_t size);
int ckvm_discard_anonymous(void *address, size_t size);

void *ckvm_map_file_private(int fd, uint64_t offset, size_t file_bytes, size_t total_size);
void *ckvm_map_file_private_at(void *at, int fd, uint64_t offset, size_t file_bytes, size_t total_size);
void *ckvm_mremap_fixed(void *old, size_t size, void *at);
int ckvm_reserve_at(void *at, size_t size);

size_t ckvm_host_page_size(void);

enum {
    CKVM_CAP_NR_VCPUS = 9,
    CKVM_CAP_NR_MEMSLOTS = 10,
    CKVM_CAP_ARM_VM_IPA_SIZE = 165,
    CKVM_CAP_MAX_VCPUS = 66,
    CKVM_CAP_IMMEDIATE_EXIT = 136,
};

int ckvm_create_vcpu(int vm_fd, unsigned long vcpu_id);
int ckvm_get_vcpu_mmap_size(int kvm_fd);
void *ckvm_map_run(int vcpu_fd, size_t mmap_size);

int ckvm_arm_vcpu_init_preferred(int vm_fd, int vcpu_fd, uint32_t features0);
enum {
    CKVM_ARM_VCPU_FEATURE_POWER_OFF = 0,
    CKVM_ARM_VCPU_FEATURE_EL1_32BIT = 1,
    CKVM_ARM_VCPU_FEATURE_PSCI_0_2 = 2,
    CKVM_ARM_VCPU_FEATURE_PMU_V3 = 3,
};

int ckvm_get_one_reg_u64(int vcpu_fd, uint64_t reg_id, uint64_t *value);
int ckvm_set_one_reg_u64(int vcpu_fd, uint64_t reg_id, uint64_t value);

int ckvm_run(int vcpu_fd);
extern int ckvm_debug_run_check;
unsigned long ckvm_debug_run_checks(void);

uint64_t ckvm_reg_x(unsigned n);
uint64_t ckvm_reg_sp_el0(void);
uint64_t ckvm_reg_pc(void);
uint64_t ckvm_reg_pstate(void);
uint64_t ckvm_reg_sp_el1(void);
uint64_t ckvm_reg_elr_el1(void);
uint64_t ckvm_reg_spsr_el1(void);
uint64_t ckvm_reg_sysreg(unsigned op0, unsigned op1, unsigned crn, unsigned crm, unsigned op2);
uint64_t ckvm_reg_timer_cnt(void);
uint64_t ckvm_reg_timer_ctl(void);

uint64_t ckvm_host_cntfrq(void);
uint64_t ckvm_host_cntvct(void);

enum { CKVM_CAP_COUNTER_OFFSET = 227 };
int ckvm_set_counter_offset(int vm_fd, uint64_t offset);

int ckvm_set_smccc_filter(int vm_fd, uint32_t base, uint32_t count, uint8_t action);
enum { CKVM_SMCCC_FILTER_FWD_TO_USER = 2 };

void ckvm_publish_timeofday(void *block, uint64_t tick, uint64_t sec, uint64_t frac, uint64_t scale,
                            uint64_t ticks_per_second);

enum {
    CKVM_EXIT_UNKNOWN = 0,
    CKVM_EXIT_EXCEPTION = 1,
    CKVM_EXIT_HYPERCALL = 3,
    CKVM_EXIT_DEBUG = 4,
    CKVM_EXIT_HLT = 5,
    CKVM_EXIT_MMIO = 6,
    CKVM_EXIT_SHUTDOWN = 8,
    CKVM_EXIT_FAIL_ENTRY = 9,
    CKVM_EXIT_INTR = 10,
    CKVM_EXIT_INTERNAL_ERROR = 17,
    CKVM_EXIT_SYSTEM_EVENT = 24,
    CKVM_EXIT_ARM_NISV = 28,
};

uint32_t ckvm_run_exit_reason(const void *run);
void ckvm_run_set_immediate_exit(void *run, uint8_t value);

uint64_t ckvm_run_mmio_phys_addr(const void *run);
uint32_t ckvm_run_mmio_len(const void *run);
uint8_t ckvm_run_mmio_is_write(const void *run);
uint64_t ckvm_run_mmio_data_u64(const void *run);
void ckvm_run_mmio_get_data(const void *run, uint8_t *out, uint32_t len);
void ckvm_run_mmio_set_data(void *run, const uint8_t *data, uint32_t len);

uint64_t ckvm_run_fail_entry_reason(const void *run);
uint32_t ckvm_run_fail_entry_cpu(const void *run);

uint32_t ckvm_run_internal_suberror(const void *run);
uint32_t ckvm_run_internal_ndata(const void *run);
uint64_t ckvm_run_internal_data(const void *run, uint32_t index);

uint32_t ckvm_run_system_event_type(const void *run);
uint32_t ckvm_run_system_event_ndata(const void *run);
uint64_t ckvm_run_system_event_data(const void *run, uint32_t index);

uint64_t ckvm_run_arm_nisv_esr_iss(const void *run);
uint64_t ckvm_run_arm_nisv_fault_ipa(const void *run);
uint64_t ckvm_run_hypercall_nr(const void *run);
uint64_t ckvm_run_hypercall_flags(const void *run);

int ckvm_kick_install(int signo);
int ckvm_kick_thread(unsigned long thread, int signo);
long ckvm_gettid(void);
void ckvm_thread_usage(long out[4]);
void ckvm_thread_times(unsigned long long out[3]);
int ckvm_task_stats(long tid, uint64_t out[8]);
long ckvm_clock_ticks(void);
int ckvm_vcpu_stats(int vcpu_fd, const char *const *names, int count, uint64_t *out);
int ckvm_kick_mask_outside_run(int vcpu_fd, int signo);
int ckvm_capture_frames(uintptr_t *out, int count);

void ckvm_clean_dcache_range(const void *address, size_t size);

uint64_t ckvm_host_id_aa64mmfr2(void);

int ckvm_watchdog_arm(uint64_t milliseconds);
int ckvm_watchdog_fired(void);

int ckvm_hwwatch_arm(uint64_t address);
void ckvm_hwwatch_disarm(void);
int ckvm_hwwatch_arm_slot(int slot, uint64_t address);
int ckvm_memcheck_start(int threads);
void ckvm_hwwatch_disarm_slot(int slot);

int ckvm_stack_sampler_install(void);
int ckvm_stack_sample(long tid, void **out, int max, int timeout_us);

int ckvm_signal_on_parent_death(int signo);

#endif

int ckvm_hostprof_thread_start(void);

#endif
