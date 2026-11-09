#import "CMPreferences.h"
#import "CMCommon.h"

// Preferences are read through CFPreferences so both the tweak (running inside
// arbitrary host apps) and the Settings bundle see the same values without
// relying on a writable container path.

static id CMPrefValue(NSString *key) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)kCMDomain);
    return value ? (__bridge_transfer id)value : nil;
}

static BOOL CMPrefBool(NSString *key, BOOL fallback) {
    id value = CMPrefValue(key);
    return value ? [value boolValue] : fallback;
}

static NSInteger CMPrefInteger(NSString *key, NSInteger fallback) {
    id value = CMPrefValue(key);
    return value ? [value integerValue] : fallback;
}

@implementation CMPreferences

+ (void)reload {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kCMDomain);
}

+ (BOOL)enabled {
    return CMPrefBool(kCMPrefEnabled, YES);
}

+ (CMActivation)activation {
    NSInteger value = CMPrefInteger(kCMPrefActivation, CMActivationBoth);
    return value == 0 ? CMActivationBoth : (CMActivation)value;
}

+ (NSInteger)maxItems {
    NSInteger value = CMPrefInteger(kCMPrefMaxItems, 200);
    return value > 0 ? value : 200;
}

+ (BOOL)ignoreLongText {
    return CMPrefBool(kCMPrefIgnoreLong, YES);
}

+ (NSInteger)maxTextLength {
    NSInteger value = CMPrefInteger(kCMPrefMaxLength, 5000);
    return value > 0 ? value : 5000;
}

+ (BOOL)ignoreSecureText {
    return CMPrefBool(kCMPrefIgnoreSecure, YES);
}

+ (NSArray<NSString *> *)ignoredApps {
    id value = CMPrefValue(kCMPrefIgnoreApps);
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}

+ (BOOL)shouldIgnoreBundleID:(NSString *)bundleID {
    if (!bundleID.length) {
        return NO;
    }
    return [[self ignoredApps] containsObject:bundleID];
}

@end
