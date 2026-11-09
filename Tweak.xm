// CopyMod - clipboard history logger with an in-keyboard panel.
//
// Injection is limited to UI processes (see CopyMod.plist). Every hook is
// guarded so that a failure leaves the stock keyboard fully functional.

#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <notify.h>

#import "CMCommon.h"
#import "CMStore.h"
#import "CMPreferences.h"
#import "CMMonitor.h"
#import "CMKeyboardBar.h"

#import <roothide.h>

static NSString *const kCMBarAssociationKey = @"com.mody.copymod.bar";

#pragma mark - Host view helpers

static CMKeyboardBar *CMBarForHostView(id hostView) {
    return objc_getAssociatedObject(hostView, (__bridge const void *)kCMBarAssociationKey);
}

static void CMSetBarForHostView(id hostView, CMKeyboardBar *bar) {
    objc_setAssociatedObject(hostView, (__bridge const void *)kCMBarAssociationKey, bar,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void CMAttachBarToHostView(id hostView) {
    if (!hostView) {
        return;
    }
    @try {
        CMKeyboardBar *bar = CMBarForHostView(hostView);
        if (![CMPreferences enabled]) {
            // Remove any previously installed UI as soon as the tweak is
            // disabled, instead of leaving it until the keyboard rebuilds.
            [bar detach];
            return;
        }
        if (!bar) {
            bar = [[CMKeyboardBar alloc] init];
            CMSetBarForHostView(hostView, bar);
        }
        [bar attachToHostView:(UIView *)hostView];
    } @catch (NSException *exception) {
        CM_LOG(@"attach failed: %@", exception.reason);
    }
}

#pragma mark - Monitor bootstrap

// Starts the pasteboard monitor on the main queue. Safe to call repeatedly.
static void CMStartMonitorIfNeeded(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
      @try {
          if (![CMPreferences enabled]) {
              CM_LOG(@"disabled by preferences, monitor not started");
              return;
          }
          [[CMMonitor sharedMonitor] start];
          CM_LOG(@"monitor ready in %@", [[NSBundle mainBundle] bundleIdentifier] ?: @"(unknown)");
      } @catch (NSException *exception) {
          CM_LOG(@"monitor bootstrap failed: %@", exception.reason);
      }
    });
}

#pragma mark - Hooks

// The keyboard classes only exist in the process that hosts the keyboard, so
// the hooks live in their own group and are initialised conditionally. The
// monitor, by contrast, runs in every injected process (see %ctor).
%group CMKeyboard

%hook UIInputSetHostView

- (void)layoutSubviews {
    %orig;
    CMAttachBarToHostView(self);
}

%end

%hook UIKeyboardImpl

- (void)setDelegate:(id)delegate {
    %orig;
    @try {
        CMStartMonitorIfNeeded();
        if ([delegate respondsToSelector:@selector(isSecureTextEntry)]) {
            BOOL secure = [[delegate valueForKey:@"isSecureTextEntry"] boolValue];
            [[CMMonitor sharedMonitor] setSecureInputActive:secure];
        }
    } @catch (NSException *exception) {
        CM_LOG(@"setDelegate handling failed: %@", exception.reason);
    }
}

%end

%end // CMKeyboard

#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        // Nothing heavy at load time: everything is deferred to the main queue.
        CMStartMonitorIfNeeded();

        // React to preference changes so enabling/disabling takes effect
        // without waiting for the next keyboard delegate callback.
        int prefsToken = 0;
        notify_register_dispatch(kCMNotificationPrefs.UTF8String, &prefsToken,
                                 dispatch_get_main_queue(), ^(int t) {
                                   [CMPreferences reload];
                                   if ([CMPreferences enabled]) {
                                       CMStartMonitorIfNeeded();
                                   } else {
                                       [[CMMonitor sharedMonitor] stop];
                                   }
                                 });

        // Install the keyboard UI hooks only where the classes are actually
        // present. Elsewhere the tweak still records copies but never touches
        // a keyboard it does not own.
        Class hostViewClass = NSClassFromString(@"UIInputSetHostView");
        Class keyboardImplClass = NSClassFromString(@"UIKeyboardImpl");
        if (hostViewClass != nil || keyboardImplClass != nil) {
            %init(CMKeyboard);
            CM_LOG(@"keyboard hooks installed in %@", [[NSBundle mainBundle] bundleIdentifier] ?: @"(unknown)");
        }
    }
}
