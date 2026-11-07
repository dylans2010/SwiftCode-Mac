#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
int main(void)
{
    @autoreleasepool {
        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        id<MTLDevice> d = MTLCreateSystemDefaultDevice();
        printf("MTLCreateSystemDefaultDevice -> %s (%.2f s)\n", d ? d.name.UTF8String : "nil", CFAbsoluteTimeGetCurrent() - t0);
        NSArray *all = MTLCopyAllDevices();
        printf("MTLCopyAllDevices -> %lu\n", (unsigned long)all.count);
        for (id<MTLDevice> x in all) printf("  %s\n", x.name.UTF8String);
    }
    return 0;
}
