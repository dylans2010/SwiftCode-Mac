#ifndef SDL_camera_h_
#define SDL_camera_h_

#include <SDL3/SDL_stdinc.h>
#include <SDL3/SDL_error.h>
#include <SDL3/SDL_pixels.h>
#include <SDL3/SDL_properties.h>
#include <SDL3/SDL_surface.h>

#include <SDL3/SDL_begin_code.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef Uint32 SDL_CameraID;

typedef struct SDL_Camera SDL_Camera;

typedef struct SDL_CameraSpec
{
    SDL_PixelFormat format;
    SDL_Colorspace colorspace;
    int width;
    int height;
    int framerate_numerator;
    int framerate_denominator;
} SDL_CameraSpec;

typedef enum SDL_CameraPosition
{
    SDL_CAMERA_POSITION_UNKNOWN,
    SDL_CAMERA_POSITION_FRONT_FACING,
    SDL_CAMERA_POSITION_BACK_FACING
} SDL_CameraPosition;

typedef enum SDL_CameraPermissionState
{
    SDL_CAMERA_PERMISSION_STATE_DENIED = -1,
    SDL_CAMERA_PERMISSION_STATE_PENDING,
    SDL_CAMERA_PERMISSION_STATE_APPROVED
} SDL_CameraPermissionState;

extern SDL_DECLSPEC int SDLCALL SDL_GetNumCameraDrivers(void);

extern SDL_DECLSPEC const char * SDLCALL SDL_GetCameraDriver(int index);

extern SDL_DECLSPEC const char * SDLCALL SDL_GetCurrentCameraDriver(void);

extern SDL_DECLSPEC SDL_CameraID * SDLCALL SDL_GetCameras(int *count);

extern SDL_DECLSPEC SDL_CameraSpec ** SDLCALL SDL_GetCameraSupportedFormats(SDL_CameraID instance_id, int *count);

extern SDL_DECLSPEC const char * SDLCALL SDL_GetCameraName(SDL_CameraID instance_id);

extern SDL_DECLSPEC SDL_CameraPosition SDLCALL SDL_GetCameraPosition(SDL_CameraID instance_id);

extern SDL_DECLSPEC SDL_Camera * SDLCALL SDL_OpenCamera(SDL_CameraID instance_id, const SDL_CameraSpec *spec);

extern SDL_DECLSPEC SDL_CameraPermissionState SDLCALL SDL_GetCameraPermissionState(SDL_Camera *camera);

extern SDL_DECLSPEC SDL_CameraID SDLCALL SDL_GetCameraID(SDL_Camera *camera);

extern SDL_DECLSPEC SDL_PropertiesID SDLCALL SDL_GetCameraProperties(SDL_Camera *camera);

extern SDL_DECLSPEC bool SDLCALL SDL_GetCameraFormat(SDL_Camera *camera, SDL_CameraSpec *spec);

extern SDL_DECLSPEC SDL_Surface * SDLCALL SDL_AcquireCameraFrame(SDL_Camera *camera, Uint64 *timestampNS);

extern SDL_DECLSPEC void SDLCALL SDL_ReleaseCameraFrame(SDL_Camera *camera, SDL_Surface *frame);

extern SDL_DECLSPEC void SDLCALL SDL_CloseCamera(SDL_Camera *camera);

#ifdef __cplusplus
}
#endif
#include <SDL3/SDL_close_code.h>

#endif
