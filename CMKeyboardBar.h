#import <UIKit/UIKit.h>
#import "CMPanelView.h"

NS_ASSUME_NONNULL_BEGIN

/// Owns the button/gesture that live inside the keyboard and the panel that
/// replaces it. One instance per keyboard window.
@interface CMKeyboardBar : NSObject <CMPanelTextInputProvider>

/// The keyboard host view this bar is currently attached to, or nil.
@property(nonatomic, weak, readonly, nullable) UIView *hostView;

/// Attaches to a keyboard host view. Returns NO when the host is unusable, in
/// which case the keyboard is left untouched. Safe to call repeatedly.
- (BOOL)attachToHostView:(UIView *)hostView;

/// Detaches from the current host and removes all added subviews/gestures.
- (void)detach;

/// Re-applies the button geometry (called when the keyboard re-lays out).
- (void)refreshButton;

@end

NS_ASSUME_NONNULL_END
