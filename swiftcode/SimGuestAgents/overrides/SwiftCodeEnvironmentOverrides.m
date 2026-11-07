#import <UIKit/UIKit.h>
#import <Accessibility/Accessibility.h>
#import <notify.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static NSDictionary *gOverrides;
static NSString *gPath;

static void say(NSString *s) {
    fprintf(stderr, "swiftcode-overrides: %s\n", s.UTF8String);
    fflush(stderr);
}

static int overrideOf(NSString *key) {
    NSDictionary *o = gOverrides;
    id v = o[key];
    if (![v respondsToSelector:@selector(boolValue)]) return -1;
    return [v boolValue] ? 1 : 0;
}

#define SWIFTCODE_INTERPOSE(replacement, original) \
    __attribute__((used)) static struct { const void *r; const void *o; } _interpose_##original \
    __attribute__((section("__DATA,__interpose"))) = {(const void *)(unsigned long)&replacement, (const void *)(unsigned long)&original};

#define SWIFTCODE_SWITCH(fn, key) \
    static BOOL swiftcode_##fn(void) { int v = overrideOf(key); return v < 0 ? fn() : (BOOL)v; } \
    SWIFTCODE_INTERPOSE(swiftcode_##fn, fn)

SWIFTCODE_SWITCH(UIAccessibilityIsReduceMotionEnabled, @"reduce-motion")
SWIFTCODE_SWITCH(UIAccessibilityIsReduceTransparencyEnabled, @"reduce-transparency")
SWIFTCODE_SWITCH(UIAccessibilityIsBoldTextEnabled, @"bold-text")
SWIFTCODE_SWITCH(UIAccessibilityIsOnOffSwitchLabelsEnabled, @"on-off-labels")
SWIFTCODE_SWITCH(UIAccessibilityButtonShapesEnabled, @"button-shapes")
SWIFTCODE_SWITCH(AXShowBordersEnabled, @"button-shapes")
SWIFTCODE_SWITCH(UIAccessibilityIsGrayscaleEnabled, @"grayscale")
SWIFTCODE_SWITCH(UIAccessibilityIsInvertColorsEnabled, @"smart-invert")
SWIFTCODE_SWITCH(UIAccessibilityShouldDifferentiateWithoutColor, @"differentiate-without-color")
SWIFTCODE_SWITCH(UIAccessibilityDarkerSystemColorsEnabled, @"increase-contrast")

static void applyToScene(UIWindowScene *scene) API_AVAILABLE(ios(17.0)) {
    id<UITraitOverrides> t = scene.traitOverrides;
    NSString *appearance = gOverrides[@"appearance"];
    if ([appearance isEqual:@"dark"]) t.userInterfaceStyle = UIUserInterfaceStyleDark;
    else if ([appearance isEqual:@"light"]) t.userInterfaceStyle = UIUserInterfaceStyleLight;
    else if ([t containsTrait:UITraitUserInterfaceStyle.class]) [t removeTrait:UITraitUserInterfaceStyle.class];

    NSString *size = gOverrides[@"dynamic-type"];
    if ([size isKindOfClass:NSString.class]) t.preferredContentSizeCategory = size;
    else if ([t containsTrait:UITraitPreferredContentSizeCategory.class]) [t removeTrait:UITraitPreferredContentSizeCategory.class];

    int contrast = overrideOf(@"increase-contrast");
    if (contrast >= 0) t.accessibilityContrast = contrast ? UIAccessibilityContrastHigh : UIAccessibilityContrastNormal;
    else if ([t containsTrait:UITraitAccessibilityContrast.class]) [t removeTrait:UITraitAccessibilityContrast.class];

    int bold = overrideOf(@"bold-text");
    if (bold >= 0) t.legibilityWeight = bold ? UILegibilityWeightBold : UILegibilityWeightRegular;
    else if ([t containsTrait:UITraitLegibilityWeight.class]) [t removeTrait:UITraitLegibilityWeight.class];
}

static void applyToAllScenes(void) {
    if (@available(iOS 17.0, *)) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:UIWindowScene.class]) applyToScene((UIWindowScene *)s);
        }
    }
}

static NSDictionary *readFile(void) {
    NSDictionary *d = gPath ? [NSDictionary dictionaryWithContentsOfFile:gPath] : nil;
    return d ?: @{};
}

static void reload(BOOL announce) {
    NSDictionary *old = gOverrides ?: @{};
    gOverrides = readFile();
    say([NSString stringWithFormat:@"%@: %@", gPath.lastPathComponent,
         gOverrides.count ? [[gOverrides.description componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]
                                componentsJoinedByString:@" "] : @"no overrides"]);
    applyToAllScenes();
    if (!announce) return;
    NSDictionary<NSString *, NSString *> *notes = @{
        @"reduce-motion": UIAccessibilityReduceMotionStatusDidChangeNotification,
        @"reduce-transparency": UIAccessibilityReduceTransparencyStatusDidChangeNotification,
        @"bold-text": UIAccessibilityBoldTextStatusDidChangeNotification,
        @"on-off-labels": UIAccessibilityOnOffSwitchLabelsDidChangeNotification,
        @"button-shapes": UIAccessibilityButtonShapesEnabledStatusDidChangeNotification,
        @"grayscale": UIAccessibilityGrayscaleStatusDidChangeNotification,
        @"smart-invert": UIAccessibilityInvertColorsStatusDidChangeNotification,
        @"differentiate-without-color": UIAccessibilityShouldDifferentiateWithoutColorDidChangeNotification,
        @"increase-contrast": UIAccessibilityDarkerSystemColorsStatusDidChangeNotification,
    };
    for (NSString *key in notes) {
        if (![old[key] isEqual:gOverrides[key]] && !(old[key] == nil && gOverrides[key] == nil)) {
            [NSNotificationCenter.defaultCenter postNotificationName:notes[key] object:nil];
            if ([key isEqual:@"button-shapes"]) {
                [NSNotificationCenter.defaultCenter postNotificationName:AXShowBordersEnabledStatusDidChangeNotification object:nil];
            }
        }
    }
}

__attribute__((constructor)) static void swiftcodeOverridesInit(void) {
    const char *dir = getenv("SWIFTCODE_ENV_OVERRIDES_DIR");
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    if (!dir || !bundleID) return;
    gPath = [[NSString stringWithUTF8String:dir] stringByAppendingPathComponent:[bundleID stringByAppendingString:@".plist"]];
    gOverrides = readFile();
    for (NSString *name in @[UISceneWillConnectNotification, UIApplicationDidFinishLaunchingNotification,
                             UISceneDidActivateNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *n) {
            (void)n;
            applyToAllScenes();
        }];
    }
    int token = 0;
    notify_register_dispatch("dev.swiftcode.environment-overrides.changed", &token, dispatch_get_main_queue(), ^(int t) {
        (void)t;
        reload(YES);
    });
    say([NSString stringWithFormat:@"loaded for %@ (%lu overrides)", bundleID, (unsigned long)gOverrides.count]);
}
