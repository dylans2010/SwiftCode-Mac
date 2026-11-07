#ifndef SDL_video_h_
#define SDL_video_h_

#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_error.h>
#include <SDL3/SDL_pixels.h>
#include <SDL3/SDL_properties.h>
#include <SDL3/SDL_rect.h>
#include <SDL3/SDL_surface.h>

#include <SDL3/SDL_begin_code.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef Uint32 SDL_DisplayID;

typedef Uint32 SDL_WindowID;

#define SDL_PROP_GLOBAL_VIDEO_WAYLAND_WL_DISPLAY_POINTER "SDL.video.wayland.wl_display"

typedef enum SDL_SystemTheme
{
    SDL_SYSTEM_THEME_UNKNOWN,
    SDL_SYSTEM_THEME_LIGHT,
    SDL_SYSTEM_THEME_DARK
} SDL_SystemTheme;

typedef struct SDL_DisplayModeData SDL_DisplayModeData;

typedef struct SDL_DisplayMode
{
    SDL_DisplayID displayID;
    SDL_PixelFormat format;
    int w;
    int h;
    float pixel_density;
    float refresh_rate;
    int refresh_rate_numerator;
    int refresh_rate_denominator;

    SDL_DisplayModeData *internal;

} SDL_DisplayMode;

typedef enum SDL_DisplayOrientation
{
    SDL_ORIENTATION_UNKNOWN,
    SDL_ORIENTATION_LANDSCAPE,
    SDL_ORIENTATION_LANDSCAPE_FLIPPED,
    SDL_ORIENTATION_PORTRAIT,
    SDL_ORIENTATION_PORTRAIT_FLIPPED
} SDL_DisplayOrientation;

typedef struct SDL_Window SDL_Window;

typedef Uint64 SDL_WindowFlags;

#define SDL_WINDOW_FULLSCREEN           SDL_UINT64_C(0x0000000000000001)
#define SDL_WINDOW_OPENGL               SDL_UINT64_C(0x0000000000000002)
#define SDL_WINDOW_OCCLUDED             SDL_UINT64_C(0x0000000000000004)
#define SDL_WINDOW_HIDDEN               SDL_UINT64_C(0x0000000000000008)
#define SDL_WINDOW_BORDERLESS           SDL_UINT64_C(0x0000000000000010)
#define SDL_WINDOW_RESIZABLE            SDL_UINT64_C(0x0000000000000020)
#define SDL_WINDOW_MINIMIZED            SDL_UINT64_C(0x0000000000000040)
#define SDL_WINDOW_MAXIMIZED            SDL_UINT64_C(0x0000000000000080)
#define SDL_WINDOW_MOUSE_GRABBED        SDL_UINT64_C(0x0000000000000100)
#define SDL_WINDOW_INPUT_FOCUS          SDL_UINT64_C(0x0000000000000200)
#define SDL_WINDOW_MOUSE_FOCUS          SDL_UINT64_C(0x0000000000000400)
#define SDL_WINDOW_EXTERNAL             SDL_UINT64_C(0x0000000000000800)
#define SDL_WINDOW_MODAL                SDL_UINT64_C(0x0000000000001000)
#define SDL_WINDOW_HIGH_PIXEL_DENSITY   SDL_UINT64_C(0x0000000000002000)
#define SDL_WINDOW_MOUSE_CAPTURE        SDL_UINT64_C(0x0000000000004000)
#define SDL_WINDOW_MOUSE_RELATIVE_MODE  SDL_UINT64_C(0x0000000000008000)
#define SDL_WINDOW_ALWAYS_ON_TOP        SDL_UINT64_C(0x0000000000010000)
#define SDL_WINDOW_UTILITY              SDL_UINT64_C(0x0000000000020000)
#define SDL_WINDOW_TOOLTIP              SDL_UINT64_C(0x0000000000040000)
#define SDL_WINDOW_POPUP_MENU           SDL_UINT64_C(0x0000000000080000)
#define SDL_WINDOW_KEYBOARD_GRABBED     SDL_UINT64_C(0x0000000000100000)
#define SDL_WINDOW_FILL_DOCUMENT        SDL_UINT64_C(0x0000000000200000)
#define SDL_WINDOW_VULKAN               SDL_UINT64_C(0x0000000010000000)
#define SDL_WINDOW_METAL                SDL_UINT64_C(0x0000000020000000)
#define SDL_WINDOW_TRANSPARENT          SDL_UINT64_C(0x0000000040000000)
#define SDL_WINDOW_NOT_FOCUSABLE        SDL_UINT64_C(0x0000000080000000)

#define SDL_WINDOWPOS_UNDEFINED_MASK    0x1FFF0000u

#define SDL_WINDOWPOS_UNDEFINED_DISPLAY(X)  (SDL_WINDOWPOS_UNDEFINED_MASK|(X))

#define SDL_WINDOWPOS_UNDEFINED         SDL_WINDOWPOS_UNDEFINED_DISPLAY(0)

#define SDL_WINDOWPOS_ISUNDEFINED(X)    (((X)&0xFFFF0000) == SDL_WINDOWPOS_UNDEFINED_MASK)

#define SDL_WINDOWPOS_CENTERED_MASK    0x2FFF0000u

#define SDL_WINDOWPOS_CENTERED_DISPLAY(X)  (SDL_WINDOWPOS_CENTERED_MASK|(X))

#define SDL_WINDOWPOS_CENTERED         SDL_WINDOWPOS_CENTERED_DISPLAY(0)

#define SDL_WINDOWPOS_ISCENTERED(X)    \
            (((X)&0xFFFF0000) == SDL_WINDOWPOS_CENTERED_MASK)

typedef enum SDL_FlashOperation
{
    SDL_FLASH_CANCEL,
    SDL_FLASH_BRIEFLY,
    SDL_FLASH_UNTIL_FOCUSED
} SDL_FlashOperation;

typedef enum SDL_ProgressState
{
    SDL_PROGRESS_STATE_INVALID = -1,
    SDL_PROGRESS_STATE_NONE,
    SDL_PROGRESS_STATE_INDETERMINATE,
    SDL_PROGRESS_STATE_NORMAL,
    SDL_PROGRESS_STATE_PAUSED,
    SDL_PROGRESS_STATE_ERROR
} SDL_ProgressState;

typedef struct SDL_GLContextState *SDL_GLContext;

typedef void *SDL_EGLDisplay;

typedef void *SDL_EGLConfig;

typedef void *SDL_EGLSurface;

typedef intptr_t SDL_EGLAttrib;

typedef int SDL_EGLint;

typedef SDL_EGLAttrib *(SDLCALL *SDL_EGLAttribArrayCallback)(void *userdata);

typedef SDL_EGLint *(SDLCALL *SDL_EGLIntArrayCallback)(void *userdata, SDL_EGLDisplay display, SDL_EGLConfig config);

typedef enum SDL_GLAttr
{
    SDL_GL_RED_SIZE,
    SDL_GL_GREEN_SIZE,
    SDL_GL_BLUE_SIZE,
    SDL_GL_ALPHA_SIZE,
    SDL_GL_BUFFER_SIZE,
    SDL_GL_DOUBLEBUFFER,
    SDL_GL_DEPTH_SIZE,
    SDL_GL_STENCIL_SIZE,
    SDL_GL_ACCUM_RED_SIZE,
    SDL_GL_ACCUM_GREEN_SIZE,
    SDL_GL_ACCUM_BLUE_SIZE,
    SDL_GL_ACCUM_ALPHA_SIZE,
    SDL_GL_STEREO,
    SDL_GL_MULTISAMPLEBUFFERS,
    SDL_GL_MULTISAMPLESAMPLES,
    SDL_GL_ACCELERATED_VISUAL,
    SDL_GL_RETAINED_BACKING,
    SDL_GL_CONTEXT_MAJOR_VERSION,
    SDL_GL_CONTEXT_MINOR_VERSION,
    SDL_GL_CONTEXT_FLAGS,
    SDL_GL_CONTEXT_PROFILE_MASK,
    SDL_GL_SHARE_WITH_CURRENT_CONTEXT,
    SDL_GL_FRAMEBUFFER_SRGB_CAPABLE,
    SDL_GL_CONTEXT_RELEASE_BEHAVIOR,
    SDL_GL_CONTEXT_RESET_NOTIFICATION,
    SDL_GL_CONTEXT_NO_ERROR,
    SDL_GL_FLOATBUFFERS,
    SDL_GL_EGL_PLATFORM
} SDL_GLAttr;

typedef Uint32 SDL_GLProfile;

#define SDL_GL_CONTEXT_PROFILE_CORE           0x0001
#define SDL_GL_CONTEXT_PROFILE_COMPATIBILITY  0x0002
#define SDL_GL_CONTEXT_PROFILE_ES             0x0004

typedef Uint32 SDL_GLContextFlag;

#define SDL_GL_CONTEXT_DEBUG_FLAG              0x0001
#define SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG 0x0002
#define SDL_GL_CONTEXT_ROBUST_ACCESS_FLAG      0x0004
#define SDL_GL_CONTEXT_RESET_ISOLATION_FLAG    0x0008

typedef Uint32 SDL_GLContextReleaseFlag;

#define SDL_GL_CONTEXT_RELEASE_BEHAVIOR_NONE   0x0000
#define SDL_GL_CONTEXT_RELEASE_BEHAVIOR_FLUSH  0x0001

typedef Uint32 SDL_GLContextResetNotification;

#define SDL_GL_CONTEXT_RESET_NO_NOTIFICATION  0x0000
#define SDL_GL_CONTEXT_RESET_LOSE_CONTEXT     0x0001

extern SDL_DECLSPEC int SDLCALL SDL_GetNumVideoDrivers(void);

extern SDL_DECLSPEC const char * SDLCALL SDL_GetVideoDriver(int index);

extern SDL_DECLSPEC const char * SDLCALL SDL_GetCurrentVideoDriver(void);

extern SDL_DECLSPEC SDL_SystemTheme SDLCALL SDL_GetSystemTheme(void);

extern SDL_DECLSPEC SDL_DisplayID * SDLCALL SDL_GetDisplays(int *count);

extern SDL_DECLSPEC SDL_DisplayID SDLCALL SDL_GetPrimaryDisplay(void);

extern SDL_DECLSPEC SDL_PropertiesID SDLCALL SDL_GetDisplayProperties(SDL_DisplayID displayID);

#define SDL_PROP_DISPLAY_HDR_ENABLED_BOOLEAN             "SDL.display.HDR_enabled"
#define SDL_PROP_DISPLAY_KMSDRM_PANEL_ORIENTATION_NUMBER "SDL.display.KMSDRM.panel_orientation"
#define SDL_PROP_DISPLAY_WAYLAND_WL_OUTPUT_POINTER       "SDL.display.wayland.wl_output"
#define SDL_PROP_DISPLAY_WINDOWS_HMONITOR_POINTER        "SDL.display.windows.hmonitor"

extern SDL_DECLSPEC const char * SDLCALL SDL_GetDisplayName(SDL_DisplayID displayID);

extern SDL_DECLSPEC bool SDLCALL SDL_GetDisplayBounds(SDL_DisplayID displayID, SDL_Rect *rect);

extern SDL_DECLSPEC bool SDLCALL SDL_GetDisplayUsableBounds(SDL_DisplayID displayID, SDL_Rect *rect);

extern SDL_DECLSPEC SDL_DisplayOrientation SDLCALL SDL_GetNaturalDisplayOrientation(SDL_DisplayID displayID);

extern SDL_DECLSPEC SDL_DisplayOrientation SDLCALL SDL_GetCurrentDisplayOrientation(SDL_DisplayID displayID);

extern SDL_DECLSPEC float SDLCALL SDL_GetDisplayContentScale(SDL_DisplayID displayID);

extern SDL_DECLSPEC SDL_DisplayMode ** SDLCALL SDL_GetFullscreenDisplayModes(SDL_DisplayID displayID, int *count);

extern SDL_DECLSPEC bool SDLCALL SDL_GetClosestFullscreenDisplayMode(SDL_DisplayID displayID, int w, int h, float refresh_rate, bool include_high_density_modes, SDL_DisplayMode *closest);

extern SDL_DECLSPEC const SDL_DisplayMode * SDLCALL SDL_GetDesktopDisplayMode(SDL_DisplayID displayID);

extern SDL_DECLSPEC const SDL_DisplayMode * SDLCALL SDL_GetCurrentDisplayMode(SDL_DisplayID displayID);

extern SDL_DECLSPEC SDL_DisplayID SDLCALL SDL_GetDisplayForPoint(const SDL_Point *point);

extern SDL_DECLSPEC SDL_DisplayID SDLCALL SDL_GetDisplayForRect(const SDL_Rect *rect);

extern SDL_DECLSPEC SDL_DisplayID SDLCALL SDL_GetDisplayForWindow(SDL_Window *window);

extern SDL_DECLSPEC float SDLCALL SDL_GetWindowPixelDensity(SDL_Window *window);

extern SDL_DECLSPEC float SDLCALL SDL_GetWindowDisplayScale(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowFullscreenMode(SDL_Window *window, const SDL_DisplayMode *mode);

extern SDL_DECLSPEC const SDL_DisplayMode * SDLCALL SDL_GetWindowFullscreenMode(SDL_Window *window);

extern SDL_DECLSPEC void * SDLCALL SDL_GetWindowICCProfile(SDL_Window *window, size_t *size);

extern SDL_DECLSPEC SDL_PixelFormat SDLCALL SDL_GetWindowPixelFormat(SDL_Window *window);

extern SDL_DECLSPEC SDL_Window ** SDLCALL SDL_GetWindows(int *count);

extern SDL_DECLSPEC SDL_Window * SDLCALL SDL_CreateWindow(const char *title, int w, int h, SDL_WindowFlags flags);

extern SDL_DECLSPEC SDL_Window * SDLCALL SDL_CreatePopupWindow(SDL_Window *parent, int offset_x, int offset_y, int w, int h, SDL_WindowFlags flags);

extern SDL_DECLSPEC SDL_Window * SDLCALL SDL_CreateWindowWithProperties(SDL_PropertiesID props);

#define SDL_PROP_WINDOW_CREATE_ALWAYS_ON_TOP_BOOLEAN               "SDL.window.create.always_on_top"
#define SDL_PROP_WINDOW_CREATE_BORDERLESS_BOOLEAN                  "SDL.window.create.borderless"
#define SDL_PROP_WINDOW_CREATE_CONSTRAIN_POPUP_BOOLEAN             "SDL.window.create.constrain_popup"
#define SDL_PROP_WINDOW_CREATE_FOCUSABLE_BOOLEAN                   "SDL.window.create.focusable"
#define SDL_PROP_WINDOW_CREATE_EXTERNAL_GRAPHICS_CONTEXT_BOOLEAN   "SDL.window.create.external_graphics_context"
#define SDL_PROP_WINDOW_CREATE_FLAGS_NUMBER                        "SDL.window.create.flags"
#define SDL_PROP_WINDOW_CREATE_FULLSCREEN_BOOLEAN                  "SDL.window.create.fullscreen"
#define SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER                       "SDL.window.create.height"
#define SDL_PROP_WINDOW_CREATE_HIDDEN_BOOLEAN                      "SDL.window.create.hidden"
#define SDL_PROP_WINDOW_CREATE_HIGH_PIXEL_DENSITY_BOOLEAN          "SDL.window.create.high_pixel_density"
#define SDL_PROP_WINDOW_CREATE_MAXIMIZED_BOOLEAN                   "SDL.window.create.maximized"
#define SDL_PROP_WINDOW_CREATE_MENU_BOOLEAN                        "SDL.window.create.menu"
#define SDL_PROP_WINDOW_CREATE_METAL_BOOLEAN                       "SDL.window.create.metal"
#define SDL_PROP_WINDOW_CREATE_MINIMIZED_BOOLEAN                   "SDL.window.create.minimized"
#define SDL_PROP_WINDOW_CREATE_MODAL_BOOLEAN                       "SDL.window.create.modal"
#define SDL_PROP_WINDOW_CREATE_MOUSE_GRABBED_BOOLEAN               "SDL.window.create.mouse_grabbed"
#define SDL_PROP_WINDOW_CREATE_OPENGL_BOOLEAN                      "SDL.window.create.opengl"
#define SDL_PROP_WINDOW_CREATE_PARENT_POINTER                      "SDL.window.create.parent"
#define SDL_PROP_WINDOW_CREATE_RESIZABLE_BOOLEAN                   "SDL.window.create.resizable"
#define SDL_PROP_WINDOW_CREATE_TITLE_STRING                        "SDL.window.create.title"
#define SDL_PROP_WINDOW_CREATE_TRANSPARENT_BOOLEAN                 "SDL.window.create.transparent"
#define SDL_PROP_WINDOW_CREATE_TOOLTIP_BOOLEAN                     "SDL.window.create.tooltip"
#define SDL_PROP_WINDOW_CREATE_UTILITY_BOOLEAN                     "SDL.window.create.utility"
#define SDL_PROP_WINDOW_CREATE_VULKAN_BOOLEAN                      "SDL.window.create.vulkan"
#define SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER                        "SDL.window.create.width"
#define SDL_PROP_WINDOW_CREATE_X_NUMBER                            "SDL.window.create.x"
#define SDL_PROP_WINDOW_CREATE_Y_NUMBER                            "SDL.window.create.y"
#define SDL_PROP_WINDOW_CREATE_COCOA_WINDOW_POINTER                "SDL.window.create.cocoa.window"
#define SDL_PROP_WINDOW_CREATE_COCOA_VIEW_POINTER                  "SDL.window.create.cocoa.view"
#define SDL_PROP_WINDOW_CREATE_WINDOWSCENE_POINTER                 "SDL.window.create.uikit.windowscene"
#define SDL_PROP_WINDOW_CREATE_WAYLAND_SURFACE_ROLE_CUSTOM_BOOLEAN "SDL.window.create.wayland.surface_role_custom"
#define SDL_PROP_WINDOW_CREATE_WAYLAND_CREATE_EGL_WINDOW_BOOLEAN   "SDL.window.create.wayland.create_egl_window"
#define SDL_PROP_WINDOW_CREATE_WAYLAND_WL_SURFACE_POINTER          "SDL.window.create.wayland.wl_surface"
#define SDL_PROP_WINDOW_CREATE_WIN32_HWND_POINTER                  "SDL.window.create.win32.hwnd"
#define SDL_PROP_WINDOW_CREATE_WIN32_PIXEL_FORMAT_HWND_POINTER     "SDL.window.create.win32.pixel_format_hwnd"
#define SDL_PROP_WINDOW_CREATE_X11_WINDOW_NUMBER                   "SDL.window.create.x11.window"
#define SDL_PROP_WINDOW_CREATE_EMSCRIPTEN_CANVAS_ID_STRING         "SDL.window.create.emscripten.canvas_id"
#define SDL_PROP_WINDOW_CREATE_EMSCRIPTEN_KEYBOARD_ELEMENT_STRING  "SDL.window.create.emscripten.keyboard_element"

extern SDL_DECLSPEC SDL_WindowID SDLCALL SDL_GetWindowID(SDL_Window *window);

extern SDL_DECLSPEC SDL_Window * SDLCALL SDL_GetWindowFromID(SDL_WindowID id);

extern SDL_DECLSPEC SDL_Window * SDLCALL SDL_GetWindowParent(SDL_Window *window);

extern SDL_DECLSPEC SDL_PropertiesID SDLCALL SDL_GetWindowProperties(SDL_Window *window);

#define SDL_PROP_WINDOW_SHAPE_POINTER                               "SDL.window.shape"
#define SDL_PROP_WINDOW_HDR_ENABLED_BOOLEAN                         "SDL.window.HDR_enabled"
#define SDL_PROP_WINDOW_SDR_WHITE_LEVEL_FLOAT                       "SDL.window.SDR_white_level"
#define SDL_PROP_WINDOW_HDR_HEADROOM_FLOAT                          "SDL.window.HDR_headroom"
#define SDL_PROP_WINDOW_ANDROID_WINDOW_POINTER                      "SDL.window.android.window"
#define SDL_PROP_WINDOW_ANDROID_SURFACE_POINTER                     "SDL.window.android.surface"
#define SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER                        "SDL.window.uikit.window"
#define SDL_PROP_WINDOW_UIKIT_METAL_VIEW_TAG_NUMBER                 "SDL.window.uikit.metal_view_tag"
#define SDL_PROP_WINDOW_UIKIT_OPENGL_FRAMEBUFFER_NUMBER             "SDL.window.uikit.opengl.framebuffer"
#define SDL_PROP_WINDOW_UIKIT_OPENGL_RENDERBUFFER_NUMBER            "SDL.window.uikit.opengl.renderbuffer"
#define SDL_PROP_WINDOW_UIKIT_OPENGL_RESOLVE_FRAMEBUFFER_NUMBER     "SDL.window.uikit.opengl.resolve_framebuffer"
#define SDL_PROP_WINDOW_KMSDRM_DEVICE_INDEX_NUMBER                  "SDL.window.kmsdrm.dev_index"
#define SDL_PROP_WINDOW_KMSDRM_DRM_FD_NUMBER                        "SDL.window.kmsdrm.drm_fd"
#define SDL_PROP_WINDOW_KMSDRM_GBM_DEVICE_POINTER                   "SDL.window.kmsdrm.gbm_dev"
#define SDL_PROP_WINDOW_COCOA_WINDOW_POINTER                        "SDL.window.cocoa.window"
#define SDL_PROP_WINDOW_COCOA_METAL_VIEW_TAG_NUMBER                 "SDL.window.cocoa.metal_view_tag"
#define SDL_PROP_WINDOW_OPENVR_OVERLAY_ID_NUMBER                    "SDL.window.openvr.overlay_id"
#define SDL_PROP_WINDOW_VIVANTE_DISPLAY_POINTER                     "SDL.window.vivante.display"
#define SDL_PROP_WINDOW_VIVANTE_WINDOW_POINTER                      "SDL.window.vivante.window"
#define SDL_PROP_WINDOW_VIVANTE_SURFACE_POINTER                     "SDL.window.vivante.surface"
#define SDL_PROP_WINDOW_WIN32_HWND_POINTER                          "SDL.window.win32.hwnd"
#define SDL_PROP_WINDOW_WIN32_HDC_POINTER                           "SDL.window.win32.hdc"
#define SDL_PROP_WINDOW_WIN32_INSTANCE_POINTER                      "SDL.window.win32.instance"
#define SDL_PROP_WINDOW_WAYLAND_DISPLAY_POINTER                     "SDL.window.wayland.display"
#define SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER                     "SDL.window.wayland.surface"
#define SDL_PROP_WINDOW_WAYLAND_VIEWPORT_POINTER                    "SDL.window.wayland.viewport"
#define SDL_PROP_WINDOW_WAYLAND_EGL_WINDOW_POINTER                  "SDL.window.wayland.egl_window"
#define SDL_PROP_WINDOW_WAYLAND_XDG_SURFACE_POINTER                 "SDL.window.wayland.xdg_surface"
#define SDL_PROP_WINDOW_WAYLAND_XDG_TOPLEVEL_POINTER                "SDL.window.wayland.xdg_toplevel"
#define SDL_PROP_WINDOW_WAYLAND_XDG_TOPLEVEL_EXPORT_HANDLE_STRING   "SDL.window.wayland.xdg_toplevel_export_handle"
#define SDL_PROP_WINDOW_WAYLAND_XDG_POPUP_POINTER                   "SDL.window.wayland.xdg_popup"
#define SDL_PROP_WINDOW_WAYLAND_XDG_POSITIONER_POINTER              "SDL.window.wayland.xdg_positioner"
#define SDL_PROP_WINDOW_X11_DISPLAY_POINTER                         "SDL.window.x11.display"
#define SDL_PROP_WINDOW_X11_SCREEN_NUMBER                           "SDL.window.x11.screen"
#define SDL_PROP_WINDOW_X11_WINDOW_NUMBER                           "SDL.window.x11.window"
#define SDL_PROP_WINDOW_EMSCRIPTEN_CANVAS_ID_STRING                 "SDL.window.emscripten.canvas_id"
#define SDL_PROP_WINDOW_EMSCRIPTEN_KEYBOARD_ELEMENT_STRING          "SDL.window.emscripten.keyboard_element"

extern SDL_DECLSPEC SDL_WindowFlags SDLCALL SDL_GetWindowFlags(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowTitle(SDL_Window *window, const char *title);

extern SDL_DECLSPEC const char * SDLCALL SDL_GetWindowTitle(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowIcon(SDL_Window *window, SDL_Surface *icon);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowPosition(SDL_Window *window, int x, int y);

extern SDL_DECLSPEC bool SDLCALL SDL_GetWindowPosition(SDL_Window *window, int *x, int *y);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowSize(SDL_Window *window, int w, int h);

extern SDL_DECLSPEC bool SDLCALL SDL_GetWindowSize(SDL_Window *window, int *w, int *h);

extern SDL_DECLSPEC bool SDLCALL SDL_GetWindowSafeArea(SDL_Window *window, SDL_Rect *rect);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowAspectRatio(SDL_Window *window, float min_aspect, float max_aspect);

extern SDL_DECLSPEC bool SDLCALL SDL_GetWindowAspectRatio(SDL_Window *window, float *min_aspect, float *max_aspect);

extern SDL_DECLSPEC bool SDLCALL SDL_GetWindowBordersSize(SDL_Window *window, int *top, int *left, int *bottom, int *right);

extern SDL_DECLSPEC bool SDLCALL SDL_GetWindowSizeInPixels(SDL_Window *window, int *w, int *h);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowMinimumSize(SDL_Window *window, int min_w, int min_h);

extern SDL_DECLSPEC bool SDLCALL SDL_GetWindowMinimumSize(SDL_Window *window, int *w, int *h);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowMaximumSize(SDL_Window *window, int max_w, int max_h);

extern SDL_DECLSPEC bool SDLCALL SDL_GetWindowMaximumSize(SDL_Window *window, int *w, int *h);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowBordered(SDL_Window *window, bool bordered);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowResizable(SDL_Window *window, bool resizable);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowAlwaysOnTop(SDL_Window *window, bool on_top);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowFillDocument(SDL_Window *window, bool fill);

extern SDL_DECLSPEC bool SDLCALL SDL_ShowWindow(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_HideWindow(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_RaiseWindow(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_MaximizeWindow(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_MinimizeWindow(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_RestoreWindow(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowFullscreen(SDL_Window *window, bool fullscreen);

extern SDL_DECLSPEC bool SDLCALL SDL_SyncWindow(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_WindowHasSurface(SDL_Window *window);

extern SDL_DECLSPEC SDL_Surface * SDLCALL SDL_GetWindowSurface(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowSurfaceVSync(SDL_Window *window, int vsync);

#define SDL_WINDOW_SURFACE_VSYNC_DISABLED 0
#define SDL_WINDOW_SURFACE_VSYNC_ADAPTIVE (-1)

extern SDL_DECLSPEC bool SDLCALL SDL_GetWindowSurfaceVSync(SDL_Window *window, int *vsync);

extern SDL_DECLSPEC bool SDLCALL SDL_UpdateWindowSurface(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_UpdateWindowSurfaceRects(SDL_Window *window, const SDL_Rect *rects, int numrects);

extern SDL_DECLSPEC bool SDLCALL SDL_DestroyWindowSurface(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowKeyboardGrab(SDL_Window *window, bool grabbed);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowMouseGrab(SDL_Window *window, bool grabbed);

extern SDL_DECLSPEC bool SDLCALL SDL_GetWindowKeyboardGrab(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_GetWindowMouseGrab(SDL_Window *window);

extern SDL_DECLSPEC SDL_Window * SDLCALL SDL_GetGrabbedWindow(void);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowMouseRect(SDL_Window *window, const SDL_Rect *rect);

extern SDL_DECLSPEC const SDL_Rect * SDLCALL SDL_GetWindowMouseRect(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowOpacity(SDL_Window *window, float opacity);

extern SDL_DECLSPEC float SDLCALL SDL_GetWindowOpacity(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowParent(SDL_Window *window, SDL_Window *parent);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowModal(SDL_Window *window, bool modal);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowFocusable(SDL_Window *window, bool focusable);

extern SDL_DECLSPEC bool SDLCALL SDL_ShowWindowSystemMenu(SDL_Window *window, int x, int y);

typedef enum SDL_HitTestResult
{
    SDL_HITTEST_NORMAL,
    SDL_HITTEST_DRAGGABLE,
    SDL_HITTEST_RESIZE_TOPLEFT,
    SDL_HITTEST_RESIZE_TOP,
    SDL_HITTEST_RESIZE_TOPRIGHT,
    SDL_HITTEST_RESIZE_RIGHT,
    SDL_HITTEST_RESIZE_BOTTOMRIGHT,
    SDL_HITTEST_RESIZE_BOTTOM,
    SDL_HITTEST_RESIZE_BOTTOMLEFT,
    SDL_HITTEST_RESIZE_LEFT
} SDL_HitTestResult;

typedef SDL_HitTestResult (SDLCALL *SDL_HitTest)(SDL_Window *win,
                                                 const SDL_Point *area,
                                                 void *data);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowHitTest(SDL_Window *window, SDL_HitTest callback, void *callback_data);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowShape(SDL_Window *window, SDL_Surface *shape);

extern SDL_DECLSPEC bool SDLCALL SDL_FlashWindow(SDL_Window *window, SDL_FlashOperation operation);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowProgressState(SDL_Window *window, SDL_ProgressState state);

extern SDL_DECLSPEC SDL_ProgressState SDLCALL SDL_GetWindowProgressState(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_SetWindowProgressValue(SDL_Window *window, float value);

extern SDL_DECLSPEC float SDLCALL SDL_GetWindowProgressValue(SDL_Window *window);

extern SDL_DECLSPEC void SDLCALL SDL_DestroyWindow(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_ScreenSaverEnabled(void);

extern SDL_DECLSPEC bool SDLCALL SDL_EnableScreenSaver(void);

extern SDL_DECLSPEC bool SDLCALL SDL_DisableScreenSaver(void);

extern SDL_DECLSPEC bool SDLCALL SDL_GL_LoadLibrary(const char *path);

extern SDL_DECLSPEC SDL_FunctionPointer SDLCALL SDL_GL_GetProcAddress(const char *proc);

extern SDL_DECLSPEC SDL_FunctionPointer SDLCALL SDL_EGL_GetProcAddress(const char *proc);

extern SDL_DECLSPEC void SDLCALL SDL_GL_UnloadLibrary(void);

extern SDL_DECLSPEC bool SDLCALL SDL_GL_ExtensionSupported(const char *extension);

extern SDL_DECLSPEC void SDLCALL SDL_GL_ResetAttributes(void);

extern SDL_DECLSPEC bool SDLCALL SDL_GL_SetAttribute(SDL_GLAttr attr, int value);

extern SDL_DECLSPEC bool SDLCALL SDL_GL_GetAttribute(SDL_GLAttr attr, int *value);

extern SDL_DECLSPEC SDL_GLContext SDLCALL SDL_GL_CreateContext(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_GL_MakeCurrent(SDL_Window *window, SDL_GLContext context);

extern SDL_DECLSPEC SDL_Window * SDLCALL SDL_GL_GetCurrentWindow(void);

extern SDL_DECLSPEC SDL_GLContext SDLCALL SDL_GL_GetCurrentContext(void);

extern SDL_DECLSPEC SDL_EGLDisplay SDLCALL SDL_EGL_GetCurrentDisplay(void);

extern SDL_DECLSPEC SDL_EGLConfig SDLCALL SDL_EGL_GetCurrentConfig(void);

extern SDL_DECLSPEC SDL_EGLSurface SDLCALL SDL_EGL_GetWindowSurface(SDL_Window *window);

extern SDL_DECLSPEC void SDLCALL SDL_EGL_SetAttributeCallbacks(SDL_EGLAttribArrayCallback platformAttribCallback,
                                                               SDL_EGLIntArrayCallback surfaceAttribCallback,
                                                               SDL_EGLIntArrayCallback contextAttribCallback, void *userdata);

extern SDL_DECLSPEC bool SDLCALL SDL_GL_SetSwapInterval(int interval);

extern SDL_DECLSPEC bool SDLCALL SDL_GL_GetSwapInterval(int *interval);

extern SDL_DECLSPEC bool SDLCALL SDL_GL_SwapWindow(SDL_Window *window);

extern SDL_DECLSPEC bool SDLCALL SDL_GL_DestroyContext(SDL_GLContext context);

#ifdef __cplusplus
}
#endif
#include <SDL3/SDL_close_code.h>

#endif
