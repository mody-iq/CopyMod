#import <UIKit/UIKit.h>
#import "CMStore.h"

NS_ASSUME_NONNULL_BEGIN

/// Supplies text insertion to the panel. The bar implements this so the panel
/// stays independent from the keyboard internals.
@protocol CMPanelTextInputProvider <NSObject>
/// Inserts text into the focused field. Returns NO when no field could take it.
- (BOOL)cm_insertText:(NSString *)text;
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
- (void)dismiss;
- (void)reloadData;

@end

NS_ASSUME_NONNULL_END
