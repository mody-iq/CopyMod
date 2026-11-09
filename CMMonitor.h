#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Watches the general pasteboard and records new text copies.
///
/// Runs in every process that loads the tweak. The clipboard is polled on a
/// background timer and also observed through UIPasteboardChangedNotification;
/// the two paths are de-duplicated through the pasteboard changeCount.
@interface CMMonitor : NSObject

+ (instancetype)sharedMonitor;

/// Starts polling. Safe to call more than once.
- (void)start;

/// Stops polling and removes observers.
- (void)stop;

/// Lets the keyboard layer mark the active input as secure so password copies
/// are never recorded.
- (void)setSecureInputActive:(BOOL)secure;

@end
NS_ASSUME_NONNULL_END
