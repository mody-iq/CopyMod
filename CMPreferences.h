#import <Foundation/Foundation.h>
#import "CMCommon.h"

NS_ASSUME_NONNULL_BEGIN

/// Reads the shared preference domain. Safe to call from any process: the
/// defaults are registered so a missing plist never yields nil.
@interface CMPreferences : NSObject

+ (BOOL)enabled;
+ (CMActivation)activation;
+ (NSInteger)maxItems;
+ (BOOL)ignoreLongText;
+ (NSInteger)maxTextLength;
+ (BOOL)ignoreSecureText;
+ (NSArray<NSString *> *)ignoredApps;

/// YES when the bundle identifier must not be recorded.
+ (BOOL)shouldIgnoreBundleID:(NSString *)bundleID;

/// Re-reads the preference file. Called on the Darwin "prefs changed" event.
+ (void)reload;

@end
NS_ASSUME_NONNULL_END
