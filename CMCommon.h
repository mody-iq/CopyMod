#ifndef CMCCOMMON_H
#define CMCCOMMON_H

#import <Foundation/Foundation.h>

#define CM_LOG(fmt, ...) NSLog(@"[CopyMod] " fmt, ##__VA_ARGS__)

// Preference domain (shared by the tweak and the Settings bundle).
static NSString *const kCMDomain = @"com.mody.copymod";

// Preference keys.
static NSString *const kCMPrefEnabled = @"enabled";
static NSString *const kCMPrefActivation = @"activation";
static NSString *const kCMPrefMaxItems = @"maxItems";
static NSString *const kCMPrefIgnoreLong = @"ignoreLongText";
static NSString *const kCMPrefMaxLength = @"maxTextLength";
static NSString *const kCMPrefIgnoreSecure = @"ignoreSecureText";
static NSString *const kCMPrefIgnoreApps = @"ignoredApps";

// Activation method bit flags (mirrors the Settings list order).
typedef NS_OPTIONS(NSUInteger, CMActivation) {
    CMActivationButton = 1 << 0,
    CMActivationGesture = 1 << 1,
    CMActivationBoth = CMActivationButton | CMActivationGesture,
};

// Darwin notification names, used for cross-process reload.
static NSString *const kCMNotificationReload = @"com.mody.copymod.reload";
static NSString *const kCMNotificationPrefs = @"com.mody.copymod.prefs";
static NSString *const kCMNotificationClear = @"com.mody.copymod.clear";
static NSString *const kCMNotificationExport = @"com.mody.copymod.export";

// Shared CFPreferences domain used to mirror the history. Sandboxed app
// processes can read this domain even when the on-disk file is out of reach.
static NSString *const kCMHistoryDomain = @"com.mody.copymod.history";
static NSString *const kCMHistoryKey = @"history";

#endif /* CMCCOMMON_H */
