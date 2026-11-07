#ifndef SDL_mutex_h_
#define SDL_mutex_h_

#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_atomic.h>
#include <SDL3/SDL_error.h>
#include <SDL3/SDL_thread.h>

#ifdef SDL_WIKI_DOCUMENTATION_SECTION

#define SDL_THREAD_ANNOTATION_ATTRIBUTE__(x)   __attribute__((x))

#elif defined(SDL_THREAD_SAFETY_ANALYSIS) && defined(__clang__) && (!defined(SWIG))
#define SDL_THREAD_ANNOTATION_ATTRIBUTE__(x)   __attribute__((x))
#else
#define SDL_THREAD_ANNOTATION_ATTRIBUTE__(x)
#endif

#define SDL_CAPABILITY(x) \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(capability(x))

#define SDL_SCOPED_CAPABILITY \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(scoped_lockable)

#define SDL_GUARDED_BY(x) \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(guarded_by(x))

#define SDL_PT_GUARDED_BY(x) \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(pt_guarded_by(x))

#define SDL_ACQUIRED_BEFORE(x) \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(acquired_before(x))

#define SDL_ACQUIRED_AFTER(x) \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(acquired_after(x))

#define SDL_REQUIRES(x) \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(requires_capability(x))

#define SDL_REQUIRES_SHARED(x) \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(requires_shared_capability(x))

#define SDL_ACQUIRE(x) \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(acquire_capability(x))

#define SDL_ACQUIRE_SHARED(x) \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(acquire_shared_capability(x))

#define SDL_RELEASE(x) \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(release_capability(x))

#define SDL_RELEASE_SHARED(x) \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(release_shared_capability(x))

#define SDL_RELEASE_GENERIC(x) \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(release_generic_capability(x))

#define SDL_TRY_ACQUIRE(x, y) \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(try_acquire_capability(x, y))

#define SDL_TRY_ACQUIRE_SHARED(x, y) \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(try_acquire_shared_capability(x, y))

#define SDL_EXCLUDES(x) \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(locks_excluded(x))

#define SDL_ASSERT_CAPABILITY(x) \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(assert_capability(x))

#define SDL_ASSERT_SHARED_CAPABILITY(x) \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(assert_shared_capability(x))

#define SDL_RETURN_CAPABILITY(x) \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(lock_returned(x))

#define SDL_NO_THREAD_SAFETY_ANALYSIS \
  SDL_THREAD_ANNOTATION_ATTRIBUTE__(no_thread_safety_analysis)

#include <SDL3/SDL_begin_code.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct SDL_Mutex SDL_Mutex;

extern SDL_DECLSPEC SDL_Mutex * SDLCALL SDL_CreateMutex(void);

extern SDL_DECLSPEC void SDLCALL SDL_LockMutex(SDL_Mutex *mutex) SDL_ACQUIRE(mutex);

extern SDL_DECLSPEC bool SDLCALL SDL_TryLockMutex(SDL_Mutex *mutex) SDL_TRY_ACQUIRE(true, mutex);

extern SDL_DECLSPEC void SDLCALL SDL_UnlockMutex(SDL_Mutex *mutex) SDL_RELEASE(mutex);

extern SDL_DECLSPEC void SDLCALL SDL_DestroyMutex(SDL_Mutex *mutex);

typedef struct SDL_RWLock SDL_RWLock;

extern SDL_DECLSPEC SDL_RWLock * SDLCALL SDL_CreateRWLock(void);

extern SDL_DECLSPEC void SDLCALL SDL_LockRWLockForReading(SDL_RWLock *rwlock) SDL_ACQUIRE_SHARED(rwlock);

extern SDL_DECLSPEC void SDLCALL SDL_LockRWLockForWriting(SDL_RWLock *rwlock) SDL_ACQUIRE(rwlock);

extern SDL_DECLSPEC bool SDLCALL SDL_TryLockRWLockForReading(SDL_RWLock *rwlock) SDL_TRY_ACQUIRE_SHARED(true, rwlock);

extern SDL_DECLSPEC bool SDLCALL SDL_TryLockRWLockForWriting(SDL_RWLock *rwlock) SDL_TRY_ACQUIRE(true, rwlock);

extern SDL_DECLSPEC void SDLCALL SDL_UnlockRWLock(SDL_RWLock *rwlock) SDL_RELEASE_GENERIC(rwlock);

extern SDL_DECLSPEC void SDLCALL SDL_DestroyRWLock(SDL_RWLock *rwlock);

typedef struct SDL_Semaphore SDL_Semaphore;

extern SDL_DECLSPEC SDL_Semaphore * SDLCALL SDL_CreateSemaphore(Uint32 initial_value);

extern SDL_DECLSPEC void SDLCALL SDL_DestroySemaphore(SDL_Semaphore *sem);

extern SDL_DECLSPEC void SDLCALL SDL_WaitSemaphore(SDL_Semaphore *sem);

extern SDL_DECLSPEC bool SDLCALL SDL_TryWaitSemaphore(SDL_Semaphore *sem);

extern SDL_DECLSPEC bool SDLCALL SDL_WaitSemaphoreTimeout(SDL_Semaphore *sem, Sint32 timeoutMS);

extern SDL_DECLSPEC void SDLCALL SDL_SignalSemaphore(SDL_Semaphore *sem);

extern SDL_DECLSPEC Uint32 SDLCALL SDL_GetSemaphoreValue(SDL_Semaphore *sem);

typedef struct SDL_Condition SDL_Condition;

extern SDL_DECLSPEC SDL_Condition * SDLCALL SDL_CreateCondition(void);

extern SDL_DECLSPEC void SDLCALL SDL_DestroyCondition(SDL_Condition *cond);

extern SDL_DECLSPEC void SDLCALL SDL_SignalCondition(SDL_Condition *cond);

extern SDL_DECLSPEC void SDLCALL SDL_BroadcastCondition(SDL_Condition *cond);

extern SDL_DECLSPEC void SDLCALL SDL_WaitCondition(SDL_Condition *cond, SDL_Mutex *mutex);

extern SDL_DECLSPEC bool SDLCALL SDL_WaitConditionTimeout(SDL_Condition *cond,
                                                SDL_Mutex *mutex, Sint32 timeoutMS);

typedef enum SDL_InitStatus
{
    SDL_INIT_STATUS_UNINITIALIZED,
    SDL_INIT_STATUS_INITIALIZING,
    SDL_INIT_STATUS_INITIALIZED,
    SDL_INIT_STATUS_UNINITIALIZING
} SDL_InitStatus;

typedef struct SDL_InitState
{
    SDL_AtomicInt status;
    SDL_ThreadID thread;
    void *reserved;
} SDL_InitState;

extern SDL_DECLSPEC bool SDLCALL SDL_ShouldInit(SDL_InitState *state);

extern SDL_DECLSPEC bool SDLCALL SDL_ShouldQuit(SDL_InitState *state);

extern SDL_DECLSPEC void SDLCALL SDL_SetInitialized(SDL_InitState *state, bool initialized);

#ifdef __cplusplus
}
#endif
#include <SDL3/SDL_close_code.h>

#endif
