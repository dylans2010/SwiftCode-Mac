#ifndef SDL_clipboard_h_
#define SDL_clipboard_h_

#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_error.h>

#include <SDL3/SDL_begin_code.h>
#ifdef __cplusplus
extern "C" {
#endif

extern SDL_DECLSPEC bool SDLCALL SDL_SetClipboardText(const char *text);

extern SDL_DECLSPEC char * SDLCALL SDL_GetClipboardText(void);

extern SDL_DECLSPEC bool SDLCALL SDL_HasClipboardText(void);

extern SDL_DECLSPEC bool SDLCALL SDL_SetPrimarySelectionText(const char *text);

extern SDL_DECLSPEC char * SDLCALL SDL_GetPrimarySelectionText(void);

extern SDL_DECLSPEC bool SDLCALL SDL_HasPrimarySelectionText(void);

typedef const void *(SDLCALL *SDL_ClipboardDataCallback)(void *userdata, const char *mime_type, size_t *size);

typedef void (SDLCALL *SDL_ClipboardCleanupCallback)(void *userdata);

extern SDL_DECLSPEC bool SDLCALL SDL_SetClipboardData(SDL_ClipboardDataCallback callback, SDL_ClipboardCleanupCallback cleanup, void *userdata, const char *const *mime_types, size_t num_mime_types);

extern SDL_DECLSPEC bool SDLCALL SDL_ClearClipboardData(void);

extern SDL_DECLSPEC void * SDLCALL SDL_GetClipboardData(const char *mime_type, size_t *size);

extern SDL_DECLSPEC bool SDLCALL SDL_HasClipboardData(const char *mime_type);

extern SDL_DECLSPEC char ** SDLCALL SDL_GetClipboardMimeTypes(size_t *num_mime_types);

#ifdef __cplusplus
}
#endif
#include <SDL3/SDL_close_code.h>

#endif
