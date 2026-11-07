#ifndef SDL_keyboard_h_
#define SDL_keyboard_h_

#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_error.h>
#include <SDL3/SDL_keycode.h>
#include <SDL3/SDL_properties.h>
#include <SDL3/SDL_rect.h>
#include <SDL3/SDL_scancode.h>
#include <SDL3/SDL_video.h>

#include <SDL3/SDL_begin_code.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef Uint32 SDL_KeyboardID;

extern SDL_DECLSPEC bool SDLCALL SDL_HasKeyboard(void);

extern SDL_DECLSPEC SDL_KeyboardID * SDLCALL SDL_GetKeyboards(int *count);

extern SDL_DECLSPEC const char * SDLCALL SDL_GetKeyboardNameForID(SDL_KeyboardID instance_id);

extern SDL_DECLSPEC SDL_Window * SDLCALL SDL_GetKeyboardFocus(void);

extern SDL_DECLSPEC const bool * SDLCALL SDL_GetKeyboardState(int *numkeys);

extern SDL_DECLSPEC void SDLCALL SDL_ResetKeyboard(void);

extern SDL_DECLSPEC SDL_Keymod SDLCALL SDL_GetModState(void);

extern SDL_DECLSPEC void SDLCALL SDL_SetModState(SDL_Keymod modstate);

extern SDL_DECLSPEC SDL_Keycode SDLCALL SDL_GetKeyFromScancode(SDL_Scancode scancode, SDL_Keymod modstate, bool key_event);

extern SDL_DECLSPEC SDL_Scancode SDLCALL SDL_GetScancodeFromKey(SDL_Keycode key, SDL_Keymod *modstate);

extern SDL_DECLSPEC bool SDLCALL SDL_SetScancodeName(SDL_Scancode scancode, const char *name);

extern SDL_DECLSPEC const char * SDLCALL SDL_GetScancodeName(SDL_Scancode scancode);

extern SDL_DECLSPEC SDL_Scancode SDLCALL SDL_GetScancodeFromName(const char *name);

extern SDL_DECLSPEC const char * SDLCALL SDL_GetKeyName(SDL_Keycode key);

extern SDL_DECLSPEC SDL_Keycode SDLCALL SDL_GetKeyFromName(const char *name);

extern SDL_DECLSPEC bool SDLCALL SDL_StartTextInput(SDL_Window *window);

typedef enum SDL_TextInputType
{
    SDL_TEXTINPUT_TYPE_TEXT,
    SDL_TEXTINPUT_TYPE_TEXT_NAME,
    SDL_TEXTINPUT_TYPE_TEXT_EMAIL,
    SDL_TEXTINPUT_TYPE_TEXT_USERNAME,
    SDL_TEXTINPUT_TYPE_TEXT_PASSWORD_HIDDEN,
    SDL_TEXTINPUT_TYPE_TEXT_PASSWORD_VISIBLE,
    SDL_TEXTINPUT_TYPE_NUMBER,
    SDL_TEXTINPUT_TYPE_NUMBER_PASSWORD_HIDDEN,
    SDL_TEXTINPUT_TYPE_NUMBER_PASSWORD_VISIBLE
} SDL_TextInputType;

typedef enum SDL_Capitalization
{
    SDL_CAPITALIZE_NONE,
    SDL_CAPITALIZE_SENTENCES,
    SDL_CAPITALIZE_WORDS,
    SDL_CAPITALIZE_LETTERS
} SDL_Capitalization;

extern SDL_DECLSPEC bool SDLCALL SDL_StartTextInputWithProperties(SDL_Window *window, SDL_PropertiesID props);

#define SDL_PROP_TEXTINPUT_TYPE_NUMBER                  "SDL.textinput.type"
#define SDL_PROP_TEXTINPUT_CAPITALIZATION_NUMBER        "SDL.textinput.capitalization"
#define SDL_PROP_TEXTINPUT_AUTOCORRECT_BOOLEAN          "SDL.textinput.autocorrect"
#define SDL_PROP_TEXTINPUT_MULTILINE_BOOLEAN            "SDL.textinput.multiline"
#define SDL_PROP_TEXTINPUT_ANDROID_INPUTTYPE_NUMBER     "SDL.textinput.android.inputtype"

extern SDL_DECLSPEC bool SDLCALL SDL_TextInputActive(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_StopTextInput(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_ClearComposition(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_SetTextInputArea(SDL_Window *window, const SDL_Rect *rect, int cursor);

extern SDL_DECLSPEC bool SDLCALL SDL_GetTextInputArea(SDL_Window *window, SDL_Rect *rect, int *cursor);

extern SDL_DECLSPEC bool SDLCALL SDL_HasScreenKeyboardSupport(void);

extern SDL_DECLSPEC bool SDLCALL SDL_ScreenKeyboardShown(SDL_Window *window);

#ifdef __cplusplus
}
#endif
#include <SDL3/SDL_close_code.h>

#endif
