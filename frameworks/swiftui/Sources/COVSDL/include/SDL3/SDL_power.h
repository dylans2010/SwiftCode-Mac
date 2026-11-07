#ifndef SDL_power_h_
#define SDL_power_h_

#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_error.h>

#include <SDL3/SDL_begin_code.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef enum SDL_PowerState
{
    SDL_POWERSTATE_ERROR = -1,
    SDL_POWERSTATE_UNKNOWN,
    SDL_POWERSTATE_ON_BATTERY,
    SDL_POWERSTATE_NO_BATTERY,
    SDL_POWERSTATE_CHARGING,
    SDL_POWERSTATE_CHARGED
} SDL_PowerState;

extern SDL_DECLSPEC SDL_PowerState SDLCALL SDL_GetPowerInfo(int *seconds, int *percent);

#ifdef __cplusplus
}
#endif
#include <SDL3/SDL_close_code.h>

#endif
