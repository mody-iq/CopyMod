#import <UIKit/UIKit.h>
#import "CMPanelView.h"

NS_ASSUME_NONNULL_BEGIN

/// Owns the button/gesture that live inside the keyboard and the panel that
/// replaces it. One instance per keyboard host view.
@interface CMKeyboardBar : NSObject <CMPanelTextInputProvider>

/// Attaches to a keyboard host view. Returns NO when the host is unusable,
/// in which case the keyboard is left untouched.
- (BOOL)attachToHostView:(UIView *)hostView;

/// Detaches from the current host and removes all added subviews/gestures.
- (void)detach;

@end
NS_ASSUME_NONNULL_END
