#ifndef SDL_pen_h_
#define SDL_pen_h_

#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_mouse.h>
#include <SDL3/SDL_touch.h>

#include <SDL3/SDL_begin_code.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef Uint32 SDL_PenID;

#define SDL_PEN_MOUSEID ((SDL_MouseID)-2)

#define SDL_PEN_TOUCHID ((SDL_TouchID)-2)

typedef Uint32 SDL_PenInputFlags;

#define SDL_PEN_INPUT_DOWN         (1u << 0)
#define SDL_PEN_INPUT_BUTTON_1     (1u << 1)
#define SDL_PEN_INPUT_BUTTON_2     (1u << 2)
#define SDL_PEN_INPUT_BUTTON_3     (1u << 3)
#define SDL_PEN_INPUT_BUTTON_4     (1u << 4)
#define SDL_PEN_INPUT_BUTTON_5     (1u << 5)
#define SDL_PEN_INPUT_ERASER_TIP   (1u << 30)
#define SDL_PEN_INPUT_IN_PROXIMITY (1u << 31)

typedef enum SDL_PenAxis
{
    SDL_PEN_AXIS_PRESSURE,
    SDL_PEN_AXIS_XTILT,
    SDL_PEN_AXIS_YTILT,
    SDL_PEN_AXIS_DISTANCE,
    SDL_PEN_AXIS_ROTATION,
    SDL_PEN_AXIS_SLIDER,
    SDL_PEN_AXIS_TANGENTIAL_PRESSURE,
    SDL_PEN_AXIS_COUNT
} SDL_PenAxis;

typedef enum SDL_PenDeviceType
{
    SDL_PEN_DEVICE_TYPE_INVALID = -1,
    SDL_PEN_DEVICE_TYPE_UNKNOWN,
    SDL_PEN_DEVICE_TYPE_DIRECT,
    SDL_PEN_DEVICE_TYPE_INDIRECT
} SDL_PenDeviceType;

extern SDL_DECLSPEC SDL_PenDeviceType SDLCALL SDL_GetPenDeviceType(SDL_PenID instance_id);

#ifdef __cplusplus
}
#endif
#include <SDL3/SDL_close_code.h>

#endif
