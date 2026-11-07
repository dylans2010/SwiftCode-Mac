#ifndef SDL_version_h_
#define SDL_version_h_

#include <SDL3/SDL_stdinc.h>

#include <SDL3/SDL_begin_code.h>
#ifdef __cplusplus
extern "C" {
#endif

#define SDL_MAJOR_VERSION   3

#define SDL_MINOR_VERSION   4

#define SDL_MICRO_VERSION   18

#define SDL_VERSIONNUM(major, minor, patch) \
    ((major) * 1000000 + (minor) * 1000 + (patch))

#define SDL_VERSIONNUM_MAJOR(version) ((version) / 1000000)

#define SDL_VERSIONNUM_MINOR(version) (((version) / 1000) % 1000)

#define SDL_VERSIONNUM_MICRO(version) ((version) % 1000)

#define SDL_VERSION \
    SDL_VERSIONNUM(SDL_MAJOR_VERSION, SDL_MINOR_VERSION, SDL_MICRO_VERSION)

#define SDL_VERSION_ATLEAST(X, Y, Z) \
    (SDL_VERSION >= SDL_VERSIONNUM(X, Y, Z))

extern SDL_DECLSPEC int SDLCALL SDL_GetVersion(void);

extern SDL_DECLSPEC const char * SDLCALL SDL_GetRevision(void);

#ifdef __cplusplus
}
#endif
#include <SDL3/SDL_close_code.h>

#endif
