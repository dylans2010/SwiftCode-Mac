#ifndef SDL_atomic_h_
#define SDL_atomic_h_

#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_platform_defines.h>

#include <SDL3/SDL_begin_code.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int SDL_SpinLock;

extern SDL_DECLSPEC bool SDLCALL SDL_TryLockSpinlock(SDL_SpinLock *lock);

extern SDL_DECLSPEC void SDLCALL SDL_LockSpinlock(SDL_SpinLock *lock);

extern SDL_DECLSPEC void SDLCALL SDL_UnlockSpinlock(SDL_SpinLock *lock);

#ifdef SDL_WIKI_DOCUMENTATION_SECTION

#define SDL_CompilerBarrier() DoCompilerSpecificReadWriteBarrier()

#elif SDL_HAS_BUILTIN(__atomic_signal_fence) || (defined(__GNUC__) && (__GNUC__ >= 5))
#define SDL_CompilerBarrier()   __atomic_signal_fence(__ATOMIC_SEQ_CST)
#elif defined(_MSC_VER) && (_MSC_VER > 1200) && !defined(__clang__)
void _ReadWriteBarrier(void);
#pragma intrinsic(_ReadWriteBarrier)
#define SDL_CompilerBarrier()   _ReadWriteBarrier()
#elif (defined(__GNUC__) && !defined(SDL_PLATFORM_EMSCRIPTEN)) || (defined(__SUNPRO_C) && (__SUNPRO_C >= 0x5120))
#define SDL_CompilerBarrier()   __asm__ __volatile__ ("" : : : "memory")
#elif defined(__WATCOMC__)
extern __inline void SDL_CompilerBarrier(void);
#pragma aux SDL_CompilerBarrier = "" parm [] modify exact [];
#else
#define SDL_CompilerBarrier()   \
{ SDL_SpinLock _tmp = 0; SDL_LockSpinlock(&_tmp); }
#endif

extern SDL_DECLSPEC void SDLCALL SDL_MemoryBarrierReleaseFunction(void);

extern SDL_DECLSPEC void SDLCALL SDL_MemoryBarrierAcquireFunction(void);

#ifdef SDL_WIKI_DOCUMENTATION_SECTION

#define SDL_MemoryBarrierRelease() SDL_MemoryBarrierReleaseFunction()

#define SDL_MemoryBarrierAcquire() SDL_MemoryBarrierAcquireFunction()

#elif SDL_HAS_BUILTIN(__atomic_thread_fence) || (defined(__GNUC__) && (__GNUC__ >= 5))
#define SDL_MemoryBarrierRelease()   __atomic_thread_fence(__ATOMIC_RELEASE)
#define SDL_MemoryBarrierAcquire()   __atomic_thread_fence(__ATOMIC_ACQUIRE)
#elif defined(__GNUC__) && (defined(__powerpc__) || defined(__ppc__))
#define SDL_MemoryBarrierRelease()   __asm__ __volatile__ ("lwsync" : : : "memory")
#define SDL_MemoryBarrierAcquire()   __asm__ __volatile__ ("lwsync" : : : "memory")
#elif defined(__GNUC__) && defined(__aarch64__)
#define SDL_MemoryBarrierRelease()   __asm__ __volatile__ ("dmb ish" : : : "memory")
#define SDL_MemoryBarrierAcquire()   __asm__ __volatile__ ("dmb ishld" : : : "memory")
#elif defined(_MSC_VER) && (defined(_M_ARM64) || defined(_M_ARM64EC))
#include <arm64intr.h>
#define SDL_MemoryBarrierRelease() __dmb(_ARM64_BARRIER_ISH)
#define SDL_MemoryBarrierAcquire() __dmb(_ARM64_BARRIER_ISHLD)
#elif defined(__GNUC__) && defined(__arm__)
#if 0
typedef void (*SDL_KernelMemoryBarrierFunc)();
#define SDL_MemoryBarrierRelease()  ((SDL_KernelMemoryBarrierFunc)0xffff0fa0)()
#define SDL_MemoryBarrierAcquire()  ((SDL_KernelMemoryBarrierFunc)0xffff0fa0)()
#else
#if defined(__ARM_ARCH_7__) || defined(__ARM_ARCH_7A__) || defined(__ARM_ARCH_7EM__) || defined(__ARM_ARCH_7R__) || defined(__ARM_ARCH_7M__) || defined(__ARM_ARCH_7S__) || defined(__ARM_ARCH_8A__)
#define SDL_MemoryBarrierRelease()   __asm__ __volatile__ ("dmb ish" : : : "memory")
#define SDL_MemoryBarrierAcquire()   __asm__ __volatile__ ("dmb ish" : : : "memory")
#elif defined(__ARM_ARCH_6__) || defined(__ARM_ARCH_6J__) || defined(__ARM_ARCH_6K__) || defined(__ARM_ARCH_6T2__) || defined(__ARM_ARCH_6Z__) || defined(__ARM_ARCH_6ZK__)
#ifdef __thumb__
#define SDL_MEMORY_BARRIER_USES_FUNCTION
#define SDL_MemoryBarrierRelease()   SDL_MemoryBarrierReleaseFunction()
#define SDL_MemoryBarrierAcquire()   SDL_MemoryBarrierAcquireFunction()
#else
#define SDL_MemoryBarrierRelease()   __asm__ __volatile__ ("mcr p15, 0, %0, c7, c10, 5" : : "r"(0) : "memory")
#define SDL_MemoryBarrierAcquire()   __asm__ __volatile__ ("mcr p15, 0, %0, c7, c10, 5" : : "r"(0) : "memory")
#endif
#else
#define SDL_MemoryBarrierRelease()   __asm__ __volatile__ ("" : : : "memory")
#define SDL_MemoryBarrierAcquire()   __asm__ __volatile__ ("" : : : "memory")
#endif
#endif
#else
#if (defined(__SUNPRO_C) && (__SUNPRO_C >= 0x5120))
#include <mbarrier.h>
#define SDL_MemoryBarrierRelease()  __machine_rel_barrier()
#define SDL_MemoryBarrierAcquire()  __machine_acq_barrier()
#else
#define SDL_MemoryBarrierRelease()  SDL_CompilerBarrier()
#define SDL_MemoryBarrierAcquire()  SDL_CompilerBarrier()
#endif
#endif

#ifdef SDL_WIKI_DOCUMENTATION_SECTION

#define SDL_CPUPauseInstruction() DoACPUPauseInACompilerAndArchitectureSpecificWay

#elif (defined(__GNUC__) || defined(__clang__)) && (defined(__i386__) || defined(__x86_64__)) && !defined(__arm64ec__)
    #define SDL_CPUPauseInstruction() __asm__ __volatile__("pause\n")
#elif (defined(__arm__) && defined(__ARM_ARCH) && __ARM_ARCH >= 7) || defined(__aarch64__)
    #define SDL_CPUPauseInstruction() __asm__ __volatile__("yield" ::: "memory")
#elif (defined(__powerpc__) || defined(__powerpc64__))
    #define SDL_CPUPauseInstruction() __asm__ __volatile__("or 27,27,27");
#elif (defined(__riscv) && __riscv_xlen == 64)
    #define SDL_CPUPauseInstruction() __asm__ __volatile__(".insn i 0x0F, 0, x0, x0, 0x010");
#elif defined(_MSC_VER) && (defined(_M_IX86) || defined(_M_X64))
    #define SDL_CPUPauseInstruction() _mm_pause()
#elif defined(_MSC_VER) && (defined(_M_ARM) || defined(_M_ARM64))
    #define SDL_CPUPauseInstruction() __yield()
#elif defined(__WATCOMC__) && defined(__386__)
    extern __inline void SDL_CPUPauseInstruction(void);
    #pragma aux SDL_CPUPauseInstruction = ".686p" ".xmm2" "pause"
#else
    #define SDL_CPUPauseInstruction()
#endif

typedef struct SDL_AtomicInt { int value; } SDL_AtomicInt;

extern SDL_DECLSPEC bool SDLCALL SDL_CompareAndSwapAtomicInt(SDL_AtomicInt *a, int oldval, int newval);

extern SDL_DECLSPEC int SDLCALL SDL_SetAtomicInt(SDL_AtomicInt *a, int v);

extern SDL_DECLSPEC int SDLCALL SDL_GetAtomicInt(SDL_AtomicInt *a);

extern SDL_DECLSPEC int SDLCALL SDL_AddAtomicInt(SDL_AtomicInt *a, int v);

#ifndef SDL_AtomicIncRef

#define SDL_AtomicIncRef(a)    SDL_AddAtomicInt(a, 1)
#endif

#ifndef SDL_AtomicDecRef

#define SDL_AtomicDecRef(a)    (SDL_AddAtomicInt(a, -1) == 1)
#endif

typedef struct SDL_AtomicU32 { Uint32 value; } SDL_AtomicU32;

extern SDL_DECLSPEC bool SDLCALL SDL_CompareAndSwapAtomicU32(SDL_AtomicU32 *a, Uint32 oldval, Uint32 newval);

extern SDL_DECLSPEC Uint32 SDLCALL SDL_SetAtomicU32(SDL_AtomicU32 *a, Uint32 v);

extern SDL_DECLSPEC Uint32 SDLCALL SDL_GetAtomicU32(SDL_AtomicU32 *a);

extern SDL_DECLSPEC Uint32 SDLCALL SDL_AddAtomicU32(SDL_AtomicU32 *a, int v);

extern SDL_DECLSPEC bool SDLCALL SDL_CompareAndSwapAtomicPointer(void **a, void *oldval, void *newval);

extern SDL_DECLSPEC void * SDLCALL SDL_SetAtomicPointer(void **a, void *v);

extern SDL_DECLSPEC void * SDLCALL SDL_GetAtomicPointer(void **a);

#ifdef __cplusplus
}
#endif

#include <SDL3/SDL_close_code.h>

#endif
