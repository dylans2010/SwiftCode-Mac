#ifndef OV_SDL_H
#define OV_SDL_H

#include <stddef.h>
#include <stdint.h>

#include <SDL3/SDL_init.h>
#include <SDL3/SDL_video.h>
#include <SDL3/SDL_events.h>
#include <SDL3/SDL_vulkan.h>
#include <SDL3/SDL_clipboard.h>
#include <SDL3/SDL_keyboard.h>
#include <SDL3/SDL_mouse.h>
#include <SDL3/SDL_surface.h>
#include <SDL3/SDL_properties.h>
#include <SDL3/SDL_error.h>
#include <SDL3/SDL_timer.h>
#include <SDL3/SDL_misc.h>
#include <SDL3/SDL_hints.h>
#include <SDL3/SDL_version.h>

#define OV_SDL_FN(name) __typeof__(SDL_##name) *name

typedef struct OVSDLAPI {
    OV_SDL_FN(Init);
    OV_SDL_FN(Quit);
    OV_SDL_FN(GetError);
    OV_SDL_FN(SetHint);
    OV_SDL_FN(GetVersion);
    OV_SDL_FN(GetCurrentVideoDriver);
    OV_SDL_FN(CreateWindow);
    OV_SDL_FN(CreatePopupWindow);
    OV_SDL_FN(DestroyWindow);
    OV_SDL_FN(GetWindowID);
    OV_SDL_FN(GetWindowSize);
    OV_SDL_FN(SetWindowSize);
    OV_SDL_FN(GetWindowSizeInPixels);
    OV_SDL_FN(GetWindowDisplayScale);
    OV_SDL_FN(SetWindowTitle);
    OV_SDL_FN(ShowWindow);
    OV_SDL_FN(GetWindowProperties);
    OV_SDL_FN(GetPointerProperty);
    OV_SDL_FN(GetNumberProperty);
    OV_SDL_FN(GetDisplayForWindow);
    OV_SDL_FN(GetCurrentDisplayMode);
    OV_SDL_FN(GetDisplayUsableBounds);
    OV_SDL_FN(SetWindowPosition);
    OV_SDL_FN(RaiseWindow);
    OV_SDL_FN(GetWindowSurface);
    OV_SDL_FN(UpdateWindowSurface);
    OV_SDL_FN(CreateSurfaceFrom);
    OV_SDL_FN(DestroySurface);
    OV_SDL_FN(ConvertSurface);
    OV_SDL_FN(LockSurface);
    OV_SDL_FN(UnlockSurface);
    OV_SDL_FN(BlitSurface);
    OV_SDL_FN(PollEvent);
    OV_SDL_FN(WaitEventTimeout);
    OV_SDL_FN(PushEvent);
    OV_SDL_FN(PumpEvents);
    OV_SDL_FN(HasEvents);
    OV_SDL_FN(RegisterEvents);
    OV_SDL_FN(StartTextInput);
    OV_SDL_FN(StopTextInput);
    OV_SDL_FN(SetTextInputArea);
    OV_SDL_FN(SetClipboardText);
    OV_SDL_FN(GetClipboardText);
    OV_SDL_FN(HasClipboardText);
    OV_SDL_FN(free);
    OV_SDL_FN(OpenURL);
    OV_SDL_FN(GetTicksNS);
    OV_SDL_FN(Vulkan_GetInstanceExtensions);
    OV_SDL_FN(Vulkan_CreateSurface);
    OV_SDL_FN(Vulkan_DestroySurface);
    OV_SDL_FN(Vulkan_GetVkGetInstanceProcAddr);
    OV_SDL_FN(Vulkan_LoadLibrary);
    OV_SDL_FN(GetSystemTheme);
    OV_SDL_FN(MinimizeWindow);
    OV_SDL_FN(GetWindowPosition);
} OVSDLAPI;

#undef OV_SDL_FN

static const uint64_t OV_SDL_WINDOW_RESIZABLE = SDL_WINDOW_RESIZABLE;
static const uint64_t OV_SDL_WINDOW_HIGH_PIXEL_DENSITY = SDL_WINDOW_HIGH_PIXEL_DENSITY;
static const uint64_t OV_SDL_WINDOW_VULKAN = SDL_WINDOW_VULKAN;
static const uint64_t OV_SDL_WINDOW_HIDDEN = SDL_WINDOW_HIDDEN;
static const uint64_t OV_SDL_WINDOW_POPUP_MENU = SDL_WINDOW_POPUP_MENU;
static const uint64_t OV_SDL_WINDOW_NOT_FOCUSABLE = SDL_WINDOW_NOT_FOCUSABLE;

const OVSDLAPI *ov_sdl_load(const char *path, char *error, size_t error_len);

const char *ov_sdl_loaded_path(void);

int ov_sdl_display_fd(const OVSDLAPI *api, SDL_Window *window);

int ov_sdl_x11_focus(const OVSDLAPI *api, SDL_Window *window);

int ov_vk_probe_surface(const OVSDLAPI *api, SDL_Window *window, char *report, size_t report_len);

#endif
