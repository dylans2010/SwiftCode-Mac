#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

#if __has_feature(objc_arc)
#error "YCRuntime.m is compiled without ARC"
#endif

id YCCreateInstance(Class cls) NS_RETURNS_RETAINED;
id YCCreateInstance(Class cls) { return class_createInstance(cls, 0); }

static void YCPlainDealloc(id self, SEL _cmd) {
    struct objc_super sup = {self, [NSObject class]};
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
}

void YCUsePlainDealloc(Class cls);
void YCUsePlainDealloc(Class cls) {
    class_addMethod(cls, sel_registerName("dealloc"), (IMP)YCPlainDealloc, "v@:");
}

void YCUseNSObjectBasics(Class cls);
void YCUseNSObjectBasics(Class cls) {
    static const char *const names[] = {
        "willChangeValueForKey:", "didChangeValueForKey:",
        "willChange:valuesAtIndexes:forKey:", "didChange:valuesAtIndexes:forKey:",
        "willChangeValueForKey:withSetMutation:usingObjects:", "didChangeValueForKey:withSetMutation:usingObjects:",
        "addObserver:forKeyPath:options:context:", "removeObserver:forKeyPath:", "removeObserver:forKeyPath:context:",
        "observationInfo", "setObservationInfo:", "isEqual:", "hash",
    };
    Class base = [NSObject class];
    for (size_t i = 0; i < sizeof names / sizeof names[0]; i++) {
        SEL sel = sel_registerName(names[i]);
        Method m = class_getInstanceMethod(base, sel);
        if (m) class_addMethod(cls, sel, method_getImplementation(m), method_getTypeEncoding(m));
    }
}
