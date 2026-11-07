#ifndef SDL_thread_h_
#define SDL_thread_h_

#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_error.h>
#include <SDL3/SDL_properties.h>

#include <SDL3/SDL_atomic.h>

#if defined(SDL_PLATFORM_WINDOWS)
#include <process.h>
#endif

#include <SDL3/SDL_begin_code.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct SDL_Thread SDL_Thread;

typedef Uint64 SDL_ThreadID;

typedef SDL_AtomicInt SDL_TLSID;

typedef enum SDL_ThreadPriority {
    SDL_THREAD_PRIORITY_LOW,
    SDL_THREAD_PRIORITY_NORMAL,
    SDL_THREAD_PRIORITY_HIGH,
    SDL_THREAD_PRIORITY_TIME_CRITICAL
} SDL_ThreadPriority;

typedef enum SDL_ThreadState
{
    SDL_THREAD_UNKNOWN,
    SDL_THREAD_ALIVE,
    SDL_THREAD_DETACHED,
    SDL_THREAD_COMPLETE
} SDL_ThreadState;

typedef int (SDLCALL *SDL_ThreadFunction) (void *data);

#ifdef SDL_WIKI_DOCUMENTATION_SECTION

extern SDL_DECLSPEC SDL_Thread * SDLCALL SDL_CreateThread(SDL_ThreadFunction fn, const char *name, void *data);

extern SDL_DECLSPEC SDL_Thread * SDLCALL SDL_CreateThreadWithProperties(SDL_PropertiesID props);

#define SDL_PROP_THREAD_CREATE_ENTRY_FUNCTION_POINTER                  "SDL.thread.create.entry_function"
#define SDL_PROP_THREAD_CREATE_NAME_STRING                             "SDL.thread.create.name"
#define SDL_PROP_THREAD_CREATE_USERDATA_POINTER                        "SDL.thread.create.userdata"
#define SDL_PROP_THREAD_CREATE_STACKSIZE_NUMBER                        "SDL.thread.create.stacksize"

#endif

#ifndef SDL_WIKI_DOCUMENTATION_SECTION
#  if defined(SDL_PLATFORM_WINDOWS)
#    ifndef SDL_BeginThreadFunction
#      define SDL_BeginThreadFunction _beginthreadex
#    endif
#    ifndef SDL_EndThreadFunction
#      define SDL_EndThreadFunction _endthreadex
#    endif
#  endif
#endif

#ifndef SDL_WIKI_DOCUMENTATION_SECTION
#  ifndef SDL_BeginThreadFunction
#    define SDL_BeginThreadFunction NULL
#  endif
#endif

#ifndef SDL_WIKI_DOCUMENTATION_SECTION
#  ifndef SDL_EndThreadFunction
#    define SDL_EndThreadFunction NULL
#  endif
#endif

#ifndef SDL_WIKI_DOCUMENTATION_SECTION
extern SDL_DECLSPEC SDL_Thread * SDLCALL SDL_CreateThreadRuntime(SDL_ThreadFunction fn, const char *name, void *data, SDL_FunctionPointer pfnBeginThread, SDL_FunctionPointer pfnEndThread);

extern SDL_DECLSPEC SDL_Thread * SDLCALL SDL_CreateThreadWithPropertiesRuntime(SDL_PropertiesID props, SDL_FunctionPointer pfnBeginThread, SDL_FunctionPointer pfnEndThread);

#define SDL_CreateThread(fn, name, data) SDL_CreateThreadRuntime((fn), (name), (data), (SDL_FunctionPointer) (SDL_BeginThreadFunction), (SDL_FunctionPointer) (SDL_EndThreadFunction))
#define SDL_CreateThreadWithProperties(props) SDL_CreateThreadWithPropertiesRuntime((props), (SDL_FunctionPointer) (SDL_BeginThreadFunction), (SDL_FunctionPointer) (SDL_EndThreadFunction))
#define SDL_PROP_THREAD_CREATE_ENTRY_FUNCTION_POINTER                  "SDL.thread.create.entry_function"
#define SDL_PROP_THREAD_CREATE_NAME_STRING                             "SDL.thread.create.name"
#define SDL_PROP_THREAD_CREATE_USERDATA_POINTER                        "SDL.thread.create.userdata"
#define SDL_PROP_THREAD_CREATE_STACKSIZE_NUMBER                        "SDL.thread.create.stacksize"
#endif

extern SDL_DECLSPEC const char * SDLCALL SDL_GetThreadName(SDL_Thread *thread);

extern SDL_DECLSPEC SDL_ThreadID SDLCALL SDL_GetCurrentThreadID(void);

extern SDL_DECLSPEC SDL_ThreadID SDLCALL SDL_GetThreadID(SDL_Thread *thread);

extern SDL_DECLSPEC bool SDLCALL SDL_SetCurrentThreadPriority(SDL_ThreadPriority priority);

extern SDL_DECLSPEC void SDLCALL SDL_WaitThread(SDL_Thread *thread, int *status);

extern SDL_DECLSPEC SDL_ThreadState SDLCALL SDL_GetThreadState(SDL_Thread *thread);

extern SDL_DECLSPEC void SDLCALL SDL_DetachThread(SDL_Thread *thread);

extern SDL_DECLSPEC void * SDLCALL SDL_GetTLS(SDL_TLSID *id);

typedef void (SDLCALL *SDL_TLSDestructorCallback)(void *value);

extern SDL_DECLSPEC bool SDLCALL SDL_SetTLS(SDL_TLSID *id, const void *value, SDL_TLSDestructorCallback destructor);

extern SDL_DECLSPEC void SDLCALL SDL_CleanupTLS(void);

#ifdef __cplusplus
}
#endif
#include <SDL3/SDL_close_code.h>

#endif
