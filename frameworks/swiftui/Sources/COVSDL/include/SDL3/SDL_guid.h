#ifndef SDL_guid_h_
#define SDL_guid_h_

#include <SDL3/SDL_stdinc.h>

#include <SDL3/SDL_begin_code.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct SDL_GUID {
    Uint8 data[16];
} SDL_GUID;

extern SDL_DECLSPEC void SDLCALL SDL_GUIDToString(SDL_GUID guid, char *pszGUID, int cbGUID);

extern SDL_DECLSPEC SDL_GUID SDLCALL SDL_StringToGUID(const char *pchGUID);

#ifdef __cplusplus
}
#endif
#include <SDL3/SDL_close_code.h>

#endif
