#ifndef SDL_timer_h_
#define SDL_timer_h_

#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_error.h>

#include <SDL3/SDL_begin_code.h>
#ifdef __cplusplus
extern "C" {
#endif

#define SDL_MS_PER_SECOND   1000

#define SDL_US_PER_SECOND   1000000

#define SDL_NS_PER_SECOND   1000000000LL

#define SDL_NS_PER_MS       1000000

#define SDL_NS_PER_US       1000

#define SDL_SECONDS_TO_NS(S)    (((Uint64)(S)) * SDL_NS_PER_SECOND)

#define SDL_NS_TO_SECONDS(NS)   ((NS) / SDL_NS_PER_SECOND)

#define SDL_MS_TO_NS(MS)        (((Uint64)(MS)) * SDL_NS_PER_MS)

#define SDL_NS_TO_MS(NS)        ((NS) / SDL_NS_PER_MS)

#define SDL_US_TO_NS(US)        (((Uint64)(US)) * SDL_NS_PER_US)

#define SDL_NS_TO_US(NS)        ((NS) / SDL_NS_PER_US)

extern SDL_DECLSPEC Uint64 SDLCALL SDL_GetTicks(void);

extern SDL_DECLSPEC Uint64 SDLCALL SDL_GetTicksNS(void);

extern SDL_DECLSPEC Uint64 SDLCALL SDL_GetPerformanceCounter(void);

extern SDL_DECLSPEC Uint64 SDLCALL SDL_GetPerformanceFrequency(void);

extern SDL_DECLSPEC void SDLCALL SDL_Delay(Uint32 ms);

extern SDL_DECLSPEC void SDLCALL SDL_DelayNS(Uint64 ns);

extern SDL_DECLSPEC void SDLCALL SDL_DelayPrecise(Uint64 ns);

typedef Uint32 SDL_TimerID;

typedef Uint32 (SDLCALL *SDL_TimerCallback)(void *userdata, SDL_TimerID timerID, Uint32 interval);

extern SDL_DECLSPEC SDL_TimerID SDLCALL SDL_AddTimer(Uint32 interval, SDL_TimerCallback callback, void *userdata);

typedef Uint64 (SDLCALL *SDL_NSTimerCallback)(void *userdata, SDL_TimerID timerID, Uint64 interval);

extern SDL_DECLSPEC SDL_TimerID SDLCALL SDL_AddTimerNS(Uint64 interval, SDL_NSTimerCallback callback, void *userdata);

extern SDL_DECLSPEC bool SDLCALL SDL_RemoveTimer(SDL_TimerID id);

#ifdef __cplusplus
}
#endif
#include <SDL3/SDL_close_code.h>

#endif
