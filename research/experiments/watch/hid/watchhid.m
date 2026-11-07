#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <malloc/malloc.h>

typedef void *(*ProbeFn)(uint64_t, uint64_t, uint64_t, uint64_t, double, double, double, double);
typedef void *(*ButtonFn)(int32_t, int32_t, int32_t);
typedef void *(*ArbFn)(int32_t, uint32_t, uint32_t, int32_t);

static id client; static BOOL dumpOnly; static dispatch_queue_t q;

static void hexdump(const char *label, void *m)
{
    size_t n = malloc_size(m);
    const uint8_t *b = m;
    printf("%s (%zu bytes)\n", label, n);
    for (size_t i = 0; i < n; i += 16) {
        printf("  %04zx:", i);
        for (size_t j = i; j < i + 16 && j < n; j++) printf(" %02x", b[j]);
        printf("\n");
    }
}

static void send(const char *label, void *m)
{
    if (!m) { printf("%s: builder returned NULL\n", label); return; }
    hexdump(label, m);
    if (dumpOnly) { free(m); return; }
    dispatch_semaphore_t s = dispatch_semaphore_create(0);
    void (^done)(NSError *) = ^(NSError *e) { if (e) printf("  error %s\n", e.description.UTF8String); dispatch_semaphore_signal(s); };
    ((void (*)(id, SEL, void *, BOOL, dispatch_queue_t, id))objc_msgSend)(client,
        NSSelectorFromString(@"sendWithMessage:freeWhenDone:completionQueue:completion:"), m, YES, q, done);
    dispatch_semaphore_wait(s, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        setvbuf(stdout, NULL, _IOLBF, 0);
        if (argc < 3) return 2;
        int a = 1;
        NSString *udid = @(argv[a++]);
        if (!strcmp(argv[a], "dump") || !strcmp(argv[a], "probe")) { dumpOnly = YES; a++; }
        const char *verb = argv[a++];
        dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator", RTLD_NOW);
        void *sk = dlopen("/Applications/Xcode.app/Contents/SharedFrameworks/SimulatorKit.framework/SimulatorKit", RTLD_NOW);
        if (!sk) { printf("no SimulatorKit: %s\n", dlerror()); return 1; }
        ProbeFn crownFn = dlsym(sk, "IndigoHIDMessageForDigitalCrownEvent");
        ProbeFn gestureFn = dlsym(sk, "IndigoHIDMessageForWatchGesture");
        ButtonFn buttonFn = dlsym(sk, "IndigoHIDMessageForButton");
        ArbFn arbFn = dlsym(sk, "IndigoHIDMessageForHIDArbitrary");
        q = dispatch_queue_create("watchhid", DISPATCH_QUEUE_SERIAL);
        if (!dumpOnly) {
            NSError *e = nil;
            id ctx = ((id (*)(id, SEL, NSString *, NSError **))objc_msgSend)(NSClassFromString(@"SimServiceContext"),
                NSSelectorFromString(@"sharedServiceContextForDeveloperDir:error:"), @"/Applications/Xcode.app/Contents/Developer", &e);
            id set = ((id (*)(id, SEL, NSError **))objc_msgSend)(ctx, NSSelectorFromString(@"defaultDeviceSetWithError:"), &e);
            NSDictionary *byUDID = ((id (*)(id, SEL))objc_msgSend)(set, NSSelectorFromString(@"devicesByUDID"));
            id dev = byUDID[[[NSUUID alloc] initWithUUIDString:udid]];
            if (!dev) { printf("no device %s\n", udid.UTF8String); return 1; }
            Class cls = NSClassFromString(@"SimulatorKit.SimDeviceLegacyHIDClient");
            client = ((id (*)(id, SEL, id, NSError **))objc_msgSend)([cls alloc], NSSelectorFromString(@"initWithDevice:error:"), dev, &e);
            if (!client) { printf("no client: %s\n", e.description.UTF8String); return 1; }
        }
        if (!strcmp(verb, "crown") && dumpOnly && a >= argc) {
            send("crown probe x=(0x11,0x22,0x33,0x44) d=(1.5,2.5,3.5,4.5)",
                 crownFn(0x11, 0x22, 0x33, 0x44, 1.5, 2.5, 3.5, 4.5));
            send("crown probe x=(0,0,0,0) d=(-7.25,0,0,0)", crownFn(0, 0, 0, 0, -7.25, 0, 0, 0));
        } else if (!strcmp(verb, "gesture") && dumpOnly && a >= argc) {
            send("gesture probe x=(0x11,0x22,0x33,0x44) d=(1.5,2.5,3.5,4.5)",
                 gestureFn(0x11, 0x22, 0x33, 0x44, 1.5, 2.5, 3.5, 4.5));
            for (uint64_t k = 0; k < 4; k++) {
                char l[64]; snprintf(l, sizeof l, "gesture probe x0=%llu", k);
                send(l, gestureFn(k, 0, 0, 0, 0, 0, 0, 0));
            }
        } else if (!strcmp(verb, "crown")) {
            double delta = atof(argv[a]);
            int n = a + 1 < argc ? atoi(argv[a + 1]) : 1;
            for (int i = 0; i < n; i++) {
                send("crown", crownFn(0, 0, 0, 0, delta, 0, 0, 0));
                usleep(16000);
            }
        } else if (!strcmp(verb, "gesture")) {
            send("gesture", gestureFn(strtoull(argv[a], NULL, 0), strtoull(argv[a + 1], NULL, 0), 0, 0, 0, 0, 0, 0));
        } else if (!strcmp(verb, "button")) {
            int s = (int)strtol(argv[a], NULL, 0);
            int ms = a + 1 < argc ? atoi(argv[a + 1]) : 100;
            send("button down", buttonFn(s, 1, 0x33));
            usleep(ms * 1000);
            send("button up", buttonFn(s, 2, 0x33));
        } else if (!strcmp(verb, "hid")) {
            uint32_t pg = (uint32_t)strtol(argv[a], NULL, 0), u = (uint32_t)strtol(argv[a + 1], NULL, 0);
            int ms = a + 2 < argc ? atoi(argv[a + 2]) : 100;
            send("hid down", arbFn(0x32, pg, u, 1));
            usleep(ms * 1000);
            send("hid up", arbFn(0x32, pg, u, 2));
        }
        usleep(200000);
        return 0;
    }
}
