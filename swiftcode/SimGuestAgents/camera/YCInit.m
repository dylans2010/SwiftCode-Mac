#import "YCCamera.h"
#include <mach-o/loader.h>
#include <stdatomic.h>

static _Atomic int gInstalled;

static BOOL YCCaptureClassesPresent(void) {
    return objc_getClass("AVCaptureSession") && objc_getClass("AVCaptureDevice") && objc_getClass("AVCaptureVideoPreviewLayer");
}

static void YCTryInstall(void) {
    if (!YCCaptureClassesPresent()) return;
    int expected = 0;
    if (!atomic_compare_exchange_strong(&gInstalled, &expected, 1)) return;
    @autoreleasepool {
        YCInstallCaptureLayer();
    }
}

static void YCImageLoaded(const struct mach_header *header) {
    (void)header;
    YCTryInstall();
}

__attribute__((constructor)) static void YCStart(void) {
    const char *service = getenv("SWIFTCODE_CAMERA_SERVICE");
    if (!service || !*service) return;
    YCDebug = getenv("SWIFTCODE_CAMERA_DEBUG") && strcmp(getenv("SWIFTCODE_CAMERA_DEBUG"), "0") != 0;
    YCTrace(@"loaded (endpoint %s)", service);
    YCTryInstall();
    if (atomic_load(&gInstalled) == 0) objc_addLoadImageFunc(YCImageLoaded);
}
