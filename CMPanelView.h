#import <UIKit/UIKit.h>
#import "CMStore.h"

NS_ASSUME_NONNULL_BEGIN

/// Supplies the responder that should receive the text chosen in the panel.
@protocol CMPanelTextInputProvider <NSObject>
/// The responder currently accepting text from the keyboard, or nil.
- (nullable id<UIKeyInput>)cm_currentTextInput;
@end

/// The clipboard-history panel.
///
/// It is a plain view rather than a view controller on purpose: the stock
/// keyboard lives in its own high-level window, so a modal view controller
/// presented from the host app would end up behind the keyboard. The panel is
/// therefore added on top of the keyboard host view, covering exactly the
/// keyboard area.
@interface CMPanelView : UIView

@property(nonatomic, weak, nullable) id<CMPanelTextInputProvider> inputProvider;

/// Height of the visible panel. Should match the on-screen keyboard height.
@property(nonatomic, assign) CGFloat panelHeight;

/// Called after the panel dismissed itself (item inserted, or close tapped).
@property(nonatomic, copy, nullable) void (^dismissHandler)(void);

- (void)presentInView:(UIView *)host;
- (void)reloadData;

@end

NS_ASSUME_NONNULL_END
