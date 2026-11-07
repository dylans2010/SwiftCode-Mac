#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static void line(NSString *s) { printf("devprobe: %s\n", s.UTF8String); fflush(stdout); }

int main(int argc, char **argv) {
    if (argc > 1) sleep((unsigned)atoi(argv[1]));
    @autoreleasepool {
        UIDevice *d = UIDevice.currentDevice;
        line([NSString stringWithFormat:@"UIDevice idiom %ld model \"%@\" systemName \"%@\" systemVersion %@",
              (long)d.userInterfaceIdiom, d.model, d.systemName, d.systemVersion]);
        UIScreen *s = UIScreen.mainScreen;
        line([NSString stringWithFormat:@"UIScreen bounds %.0fx%.0f nativeBounds %.0fx%.0f scale %.1f nativeScale %.1f maxFPS %ld",
              s.bounds.size.width, s.bounds.size.height, s.nativeBounds.size.width, s.nativeBounds.size.height,
              s.scale, s.nativeScale, (long)s.maximumFramesPerSecond]);
        void *mg = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW);
        CFTypeRef (*copyAnswer)(CFStringRef) = mg ? (CFTypeRef (*)(CFStringRef))dlsym(mg, "MGCopyAnswer") : NULL;
        for (NSString *q in @[@"DeviceClass", @"ProductType", @"DeviceName", @"DeviceSupportsEnhancedMultitasking",
                              @"hardware-keyboard", @"ipad", @"telephony", @"main-screen-width", @"main-screen-height",
                              @"main-screen-scale", @"ArtworkTraits"]) {
            if (!copyAnswer) { line(@"MobileGestalt: MGCopyAnswer not found"); break; }
            CFTypeRef v = copyAnswer((__bridge CFStringRef)q);
            id o = CFBridgingRelease(v);
            NSString *text = [[o description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            line([NSString stringWithFormat:@"MG %@ = %@", q, o ? text : @"(nil)"]);
        }
    }
    const char *root = getenv("SIMULATOR_ROOT");
    char path[1024];
    snprintf(path, sizeof path, "%s/bin/launchctl", root ? root : "");
    char *args[] = {"launchctl", "list", NULL};
    pid_t pid;
    int rc = posix_spawn(&pid, path, NULL, NULL, args, environ);
    if (rc != 0) { printf("devprobe: cannot run %s: %d\n", path, rc); return 0; }
    int status = 0;
    waitpid(pid, &status, 0);
    printf("devprobe: launchctl list ended (%d)\n", status);
    return 0;
}
