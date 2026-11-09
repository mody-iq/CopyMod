#import "CMMonitor.h"
#import "CMCommon.h"
#import "CMStore.h"
#import "CMPreferences.h"

#import <UIKit/UIKit.h>
#import <notify.h>

static const NSTimeInterval kCMPollInterval = 1.0;

@interface CMMonitor ()
@property(nonatomic, assign) NSInteger lastChangeCount;
@property(nonatomic, assign) BOOL running;
@property(nonatomic, assign) BOOL secureInputActive;
@property(nonatomic, assign) int prefsToken;
@property(nonatomic, assign) int clearToken;
@property(nonatomic, assign) int exportToken;
@end

@implementation CMMonitor

+ (instancetype)sharedMonitor {
    static CMMonitor *monitor;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      monitor = [[CMMonitor alloc] init];
    });
    return monitor;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lastChangeCount = -1;
        _prefsToken = -1;
        _clearToken = -1;
        _exportToken = -1;
    }
    return self;
}

#pragma mark - Lifecycle

- (void)start {
    if (self.running) {
        return;
    }
    self.running = YES;

    // Seed the changeCount so an existing clipboard value is not re-recorded.
    @try {
        self.lastChangeCount = (NSInteger)[UIPasteboard generalPasteboard].changeCount;
    } @catch (__unused NSException *exception) {
        self.lastChangeCount = -1;
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pasteboardChanged:)
                                                 name:UIPasteboardChangedNotification
                                               object:nil];

    [self scheduleTimer];

    __weak typeof(self) weakSelf = self;
    int token = 0;
    notify_register_dispatch(kCMNotificationPrefs.UTF8String, &token,
                             dispatch_get_main_queue(), ^(int t) {
                               [CMPreferences reload];
                               (void)weakSelf;
                             });
    self.prefsToken = token;

    // Only the recording process (SpringBoard) acts on clear/export requests
    // coming from the settings bundle.
    if ([CMStore canRecord]) {
        int clearToken = 0;
        notify_register_dispatch(kCMNotificationClear.UTF8String, &clearToken,
                                 dispatch_get_main_queue(), ^(int t) {
                                   [[CMStore sharedStore] clearAll];
                                 });
        self.clearToken = clearToken;

        int exportToken = 0;
        notify_register_dispatch(kCMNotificationExport.UTF8String, &exportToken,
                                 dispatch_get_main_queue(), ^(int t) {
                                   [[CMStore sharedStore] exportToTextFile];
                                 });
        self.exportToken = exportToken;
    }

    CM_LOG(@"monitor started (pid %d)", getpid());
}

- (void)stop {
    if (!self.running) {
        return;
    }
    self.running = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(poll) object:nil];
    if (self.prefsToken >= 0) {
        notify_cancel(self.prefsToken);
        self.prefsToken = -1;
    }
    if (self.clearToken >= 0) {
        notify_cancel(self.clearToken);
        self.clearToken = -1;
    }
    if (self.exportToken >= 0) {
        notify_cancel(self.exportToken);
        self.exportToken = -1;
    }
}

- (void)scheduleTimer {
    if (!self.running) {
        return;
    }
    // -performSelector keeps the timer on the current run loop without
    // retaining the monitor through an NSTimer block.
    [self performSelector:@selector(poll) withObject:nil afterDelay:kCMPollInterval];
}

#pragma mark - Polling

- (void)poll {
    if (!self.running) {
        return;
    }
    [self captureIfChanged];
    [self scheduleTimer];
}

- (void)pasteboardChanged:(NSNotification *)notification {
    // Notification is delivered on an arbitrary thread; hop to main and read
    // the pasteboard once the change is committed.
    dispatch_async(dispatch_get_main_queue(), ^{
      [self captureIfChanged];
    });
}

- (void)captureIfChanged {
    if (![CMPreferences enabled]) {
        return;
    }
    // Only the process that can write the shared history records copies.
    // In every other process the monitor is a no-op so we never touch the
    // pasteboard needlessly.
    if (![CMStore canRecord]) {
        return;
    }

    NSInteger changeCount = 0;
    NSString *text = nil;
    @try {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        changeCount = (NSInteger)pasteboard.changeCount;
        if (changeCount == self.lastChangeCount) {
            return;
        }
        self.lastChangeCount = changeCount;
        text = pasteboard.string;
    } @catch (__unused NSException *exception) {
        return;
    }

    if (![text isKindOfClass:[NSString class]] || text.length == 0) {
        return;
    }
    if ([CMPreferences ignoreSecureText] && [self isSecureInputActive]) {
        return;
    }
    if ([CMPreferences ignoreLongText] && (NSInteger)text.length > [CMPreferences maxTextLength]) {
        return;
    }

    NSString *bundleID = [self frontmostBundleIdentifier];
    if ([CMPreferences shouldIgnoreBundleID:bundleID]) {
        return;
    }

    [[CMStore sharedStore] recordText:text sourceBundleID:bundleID];

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kCMNotificationReload, nil, nil, YES);
}

- (void)setSecureInputActive:(BOOL)secure {
    _secureInputActive = secure;
}

- (BOOL)isSecureInputActive {
    @try {
        // Ask the active keyboard instance for the current input traits; this
        // is where secure-entry state lives for the focused field.
        Class impl = NSClassFromString(@"UIKeyboardImpl");
        id instance = [impl respondsToSelector:@selector(activeInstance)]
                          ? [impl performSelector:@selector(activeInstance)]
                          : nil;
        id traits = [instance respondsToSelector:@selector(textInputTraits)]
                        ? [instance performSelector:@selector(textInputTraits)]
                        : nil;
        if ([traits respondsToSelector:@selector(isSecureTextEntry)]) {
            return [[traits valueForKey:@"isSecureTextEntry"] boolValue];
        }
    } @catch (__unused NSException *exception) {
    }
    // Fall back to whatever the keyboard layer last observed.
    return _secureInputActive;
}

#pragma mark - Foreground app

- (NSString *)frontmostBundleIdentifier {
    @try {
        // Inside an app the bundle identifier is unambiguous.
        NSString *ownBundle = [[NSBundle mainBundle] bundleIdentifier];
        if (ownBundle.length && ![ownBundle isEqualToString:@"com.apple.springboard"]) {
            return ownBundle;
        }

        // In SpringBoard resolve the foreground application defensively.
        id application = [[UIApplication sharedApplication] performSelector:@selector(_accessibilityFrontMostApplication)];
        if (application && [application respondsToSelector:@selector(bundleIdentifier)]) {
            return [application performSelector:@selector(bundleIdentifier)];
        }
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

@end
