#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <IOSurface/IOSurfaceRef.h>
#import <QuartzCore/QuartzCore.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <pthread.h>

NS_ASSUME_NONNULL_BEGIN

extern BOOL YCDebug;
void YCLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
#define YCTrace(...) do { if (YCDebug) YCLog(__VA_ARGS__); } while (0)

@interface YCCameraInfo : NSObject
@property(nonatomic, copy) NSString *uniqueID, *localizedName, *modelID, *manufacturer, *deviceType;
@property(nonatomic) NSInteger position;
@property(nonatomic, copy) NSArray<NSDictionary *> *formats;
@end

typedef struct {
    uint32_t stream;
    uint64_t sequence;
    uint32_t surfaceID, slot, seed, width, height, pixelFormat, dropped, flags;
    uint64_t presentationTicks, durationTicks;
} YCFrameInfo;

enum {
    YCStatusOK = 0, YCStatusNoDevice = 1, YCStatusBusy = 2, YCStatusBadRequest = 3, YCStatusFailed = 4,
    YCEventInterrupted = 1, YCEventInterruptionEnded = 2, YCEventDisconnected = 3, YCEventReconnected = 4, YCEventFailed = 5,
};

typedef struct {
    uint32_t status, stream, width, height, fpsMilli, pixelFormat;
} YCStartReply;

NSArray<YCCameraInfo *> *YCHostDevices(void);
YCStartReply YCHostStart(uint32_t width, uint32_t height, double fps, OSType pixelFormat);
void YCHostStop(uint32_t stream);
void YCHostRelease(uint32_t stream, uint32_t slot, uint64_t sequence);
extern void (^_Nullable YCFrameHandler)(YCFrameInfo frame);
extern void (^_Nullable YCEventHandler)(uint32_t stream, uint32_t kind, uint32_t width, uint32_t height);

CVPixelBufferRef _Nullable YCCreatePixelBuffer(YCFrameInfo frame) CF_RETURNS_RETAINED;
void YCForgetSurfaces(void);

void yc_transform_plane(const uint8_t *src, size_t srcStride, size_t width, size_t height, size_t bpe,
                        uint8_t *dst, size_t dstStride, int angle, int mirror);
void yc_420_to_bgra(const uint8_t *y, size_t yStride, const uint8_t *cbcr, size_t cStride, size_t width, size_t height,
                    int fullRange, uint8_t *dst, size_t dstStride);

void YCInstallCaptureLayer(void);

NS_ASSUME_NONNULL_END
