#ifndef SDL_init_h_
#define SDL_init_h_

#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_error.h>
#include <SDL3/SDL_events.h>

#include <SDL3/SDL_begin_code.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef Uint32 SDL_InitFlags;

#define SDL_INIT_AUDIO      0x00000010u
#define SDL_INIT_VIDEO      0x00000020u
#define SDL_INIT_JOYSTICK   0x00000200u
#define SDL_INIT_HAPTIC     0x00001000u
#define SDL_INIT_GAMEPAD    0x00002000u
#define SDL_INIT_EVENTS     0x00004000u
#define SDL_INIT_SENSOR     0x00008000u
#define SDL_INIT_CAMERA     0x00010000u

typedef enum SDL_AppResult
{
    SDL_APP_CONTINUE,
    SDL_APP_SUCCESS,
    SDL_APP_FAILURE
} SDL_AppResult;

typedef SDL_AppResult (SDLCALL *SDL_AppInit_func)(void **appstate, int argc, char *argv[]);

typedef SDL_AppResult (SDLCALL *SDL_AppIterate_func)(void *appstate);

typedef SDL_AppResult (SDLCALL *SDL_AppEvent_func)(void *appstate, SDL_Event *event);

typedef void (SDLCALL *SDL_AppQuit_func)(void *appstate, SDL_AppResult result);

extern SDL_DECLSPEC bool SDLCALL SDL_Init(SDL_InitFlags flags);

extern SDL_DECLSPEC bool SDLCALL SDL_InitSubSystem(SDL_InitFlags flags);

extern SDL_DECLSPEC void SDLCALL SDL_QuitSubSystem(SDL_InitFlags flags);

extern SDL_DECLSPEC SDL_InitFlags SDLCALL SDL_WasInit(SDL_InitFlags flags);

extern SDL_DECLSPEC void SDLCALL SDL_Quit(void);

extern SDL_DECLSPEC bool SDLCALL SDL_IsMainThread(void);

typedef void (SDLCALL *SDL_MainThreadCallback)(void *userdata);

extern SDL_DECLSPEC bool SDLCALL SDL_RunOnMainThread(SDL_MainThreadCallback callback, void *userdata, bool wait_complete);

extern SDL_DECLSPEC bool SDLCALL SDL_SetAppMetadata(const char *appname, const char *appversion, const char *appidentifier);

extern SDL_DECLSPEC bool SDLCALL SDL_SetAppMetadataProperty(const char *name, const char *value);

#define SDL_PROP_APP_METADATA_NAME_STRING         "SDL.app.metadata.name"
#define SDL_PROP_APP_METADATA_VERSION_STRING      "SDL.app.metadata.version"
#define SDL_PROP_APP_METADATA_IDENTIFIER_STRING   "SDL.app.metadata.identifier"
#define SDL_PROP_APP_METADATA_CREATOR_STRING      "SDL.app.metadata.creator"
#define SDL_PROP_APP_METADATA_COPYRIGHT_STRING    "SDL.app.metadata.copyright"
#define SDL_PROP_APP_METADATA_URL_STRING          "SDL.app.metadata.url"
#define SDL_PROP_APP_METADATA_TYPE_STRING         "SDL.app.metadata.type"

extern SDL_DECLSPEC const char * SDLCALL SDL_GetAppMetadataProperty(const char *name);

#ifdef __cplusplus
}
#endif
#include <SDL3/SDL_close_code.h>

#endif
