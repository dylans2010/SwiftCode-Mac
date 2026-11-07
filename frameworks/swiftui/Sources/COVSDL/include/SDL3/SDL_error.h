#ifndef SDL_error_h_
#define SDL_error_h_

#include <SDL3/SDL_stdinc.h>

#include <SDL3/SDL_begin_code.h>
#ifdef __cplusplus
extern "C" {
#endif

extern SDL_DECLSPEC bool SDLCALL SDL_SetError(SDL_PRINTF_FORMAT_STRING const char *fmt, ...) SDL_PRINTF_VARARG_FUNC(1);

extern SDL_DECLSPEC bool SDLCALL SDL_SetErrorV(SDL_PRINTF_FORMAT_STRING const char *fmt, va_list ap) SDL_PRINTF_VARARG_FUNCV(1);

extern SDL_DECLSPEC bool SDLCALL SDL_OutOfMemory(void);

extern SDL_DECLSPEC const char * SDLCALL SDL_GetError(void);

extern SDL_DECLSPEC bool SDLCALL SDL_ClearError(void);

#define SDL_Unsupported()               SDL_SetError("That operation is not supported")

#define SDL_InvalidParamError(param)    SDL_SetError("Parameter '%s' is invalid", (param))

#ifdef __cplusplus
}
#endif
#include <SDL3/SDL_close_code.h>

#endif
