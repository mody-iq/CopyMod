#import "CMKeyboardBar.h"
#import "CMCommon.h"
#import "CMStore.h"
#import "CMPreferences.h"
#import "CMMonitor.h"

#import <objc/runtime.h>

// Minimal declarations of the private keyboard class we query. Declared here
// (rather than imported) so the header chain of TextInputUI is not pulled in.
@interface UIKeyboardImpl : NSObject
+ (instancetype)activeInstance;
+ (CGSize)sizeForInterfaceOrientation:(NSInteger)orientation;
- (id)inputDelegate;
- (id)textInputTraits;
@end

static const CGFloat kCMButtonSize = 34;
static const CGFloat kCMButtonInset = 6;
static NSString *const kCMButtonAccessibilityLabel = @"Clipboard history";

@interface CMKeyboardBar () <UIGestureRecognizerDelegate>
@property(nonatomic, weak) UIView *hostView;
@property(nonatomic, strong) UIButton *button;
@property(nonatomic, strong) UISwipeGestureRecognizer *swipe;
@property(nonatomic, strong) CMPanelView *panel;
@property(nonatomic, assign) BOOL presenting;
@end

@implementation CMKeyboardBar

#pragma mark - Attach / detach

- (BOOL)attachToHostView:(UIView *)hostView {
    if (!hostView) {
        return NO;
    }

    // -layoutSubviews is called on every keyboard pass, so the attach path must
    // be idempotent: on a repeat call we only refresh the button geometry.
    if (self.hostView == hostView) {
        if (self.button && self.button.superview != hostView) {
            // The keyboard rebuilt its subviews; re-attach our button.
            [hostView addSubview:self.button];
            [hostView bringSubviewToFront:self.button];
        }
        if (self.swipe && self.swipe.view != hostView) {
            [hostView addGestureRecognizer:self.swipe];
        }
        if (self.button) {
            [self layoutButtonForHostView:hostView];
        }
        // The keyboard re-lays its own subviews on every pass; keep our panel
        // above them so it is never hidden behind the keys.
        if (self.panel && self.panel.superview == hostView) {
            [hostView bringSubviewToFront:self.panel];
        }
        return YES;
    }

    [self detach];
    self.hostView = hostView;

    CMActivation activation = [CMPreferences activation];

    if (activation & CMActivationButton) {
        [self installButtonInHostView:hostView];
    }
    if (activation & CMActivationGesture) {
        [self installGestureInHostView:hostView];
    }
    return YES;
}

- (void)detach {
    [self.button removeFromSuperview];
    self.button = nil;
    if (self.swipe) {
        [self.swipe.view removeGestureRecognizer:self.swipe];
        self.swipe = nil;
    }
    self.hostView = nil;
}

#pragma mark - Button

- (void)installButtonInHostView:(UIView *)hostView {
    if (self.button && self.button.superview == hostView) {
        return;
    }
    [self.button removeFromSuperview];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.accessibilityLabel = kCMButtonAccessibilityLabel;
    button.tintColor = [UIColor labelColor];
    button.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.12];
    button.layer.cornerRadius = kCMButtonSize / 2;
    button.clipsToBounds = YES;
    [button setImage:[UIImage systemImageNamed:@"doc.on.clipboard"] forState:UIControlStateNormal];
    [button addTarget:self action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];
    // Pin to the top-right corner and keep it there across resizes/rotation.
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self layoutButtonForHostView:hostView];
    [hostView addSubview:button];
    [hostView bringSubviewToFront:button];
    self.button = button;
}

- (void)layoutButtonForHostView:(UIView *)hostView {
    CGFloat width = CGRectGetWidth(hostView.bounds);
    self.button.frame = CGRectMake(width - kCMButtonSize - kCMButtonInset, kCMButtonInset,
                                   kCMButtonSize, kCMButtonSize);
}

#pragma mark - Gesture

- (void)installGestureInHostView:(UIView *)hostView {
    UISwipeGestureRecognizer *swipe =
        [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
    swipe.numberOfTouchesRequired = 2;
    swipe.direction = UISwipeGestureRecognizerDirectionUp;
    // Do not swallow key touches; only claim the two-finger swipe.
    swipe.cancelsTouchesInView = NO;
    swipe.delaysTouchesBegan = NO;
    swipe.delaysTouchesEnded = NO;
    // Let the swipe coexist with the keyboard's own recognizers instead of
    // being blocked by them.
    swipe.delegate = self;
    [hostView addGestureRecognizer:swipe];
    self.swipe = swipe;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (void)handleSwipe:(UISwipeGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized) {
        [self openPanel];
    }
}

#pragma mark - Panel presentation

- (void)openPanel {
    if (self.presenting || !self.hostView) {
        return;
    }
    self.presenting = YES;

    // The panel is added on top of the keyboard host view, not presented modally:
    // the keyboard lives in its own high-level window, so a view controller
    // presented from the host app would render behind it.
    CMPanelView *panel = [[CMPanelView alloc] initWithFrame:self.hostView.bounds];
    panel.inputProvider = self;
    panel.panelHeight = [self keyboardHeight];
    __weak typeof(self) weakSelf = self;
    panel.dismissHandler = ^{
      // Drop the bar's reference so the dismissed panel can be deallocated.
      weakSelf.panel = nil;
    };
    [panel presentInView:self.hostView];
    self.panel = panel;
    self.presenting = NO;
}

- (CGFloat)keyboardHeight {
    if (self.hostView) {
        CGFloat height = CGRectGetHeight(self.hostView.bounds);
        if (height > 60) {
            return height;
        }
    }
    @try {
        Class impl = NSClassFromString(@"UIKeyboardImpl");
        if (impl && [impl respondsToSelector:@selector(sizeForInterfaceOrientation:)]) {
            CGSize size = [impl sizeForInterfaceOrientation:UIInterfaceOrientationPortrait];
            if (size.height > 60) {
                return size.height;
            }
        }
    } @catch (__unused NSException *exception) {
    }
    return 300;
}

#pragma mark - View controller lookup

- (UIWindow *)activeAppWindow {
    UIApplication *application = UIApplication.sharedApplication;
    // Prefer a foreground-scene key window that is not the keyboard window.
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow && ![self windowIsKeyboardWindow:window]) {
                return window;
            }
        }
    }
    for (UIWindow *window in application.windows) {
        if (window.isKeyWindow && ![self windowIsKeyboardWindow:window]) {
            return window;
        }
    }
    return application.windows.firstObject;
}

- (BOOL)windowIsKeyboardWindow:(UIWindow *)window {
    return [NSStringFromClass(window.class) containsString:@"KeyboardWindow"];
}

#pragma mark - CMPanelTextInputProvider

- (id<UIKeyInput>)cm_currentTextInput {
    // 1. Ask the active keyboard for its input delegate.
    @try {
        Class impl = NSClassFromString(@"UIKeyboardImpl");
        id instance = [impl respondsToSelector:@selector(activeInstance)]
                          ? [impl performSelector:@selector(activeInstance)]
                          : nil;
        if (instance) {
            id candidate = [instance respondsToSelector:@selector(inputDelegate)]
                               ? [instance performSelector:@selector(inputDelegate)]
                               : nil;
            if ([candidate conformsToProtocol:@protocol(UIKeyInput)]) {
                [self updateSecureStateFromResponder:candidate];
                return candidate;
            }
        }
    } @catch (__unused NSException *exception) {
    }

    // 2. Fall back to a first-responder search in the app's windows.
    UIResponder *responder = [self findFirstResponderInView:[self activeAppWindow]];
    if ([responder conformsToProtocol:@protocol(UIKeyInput)]) {
        [self updateSecureStateFromResponder:responder];
        return (id<UIKeyInput>)responder;
    }
    return nil;
}

- (void)updateSecureStateFromResponder:(id)responder {
    BOOL secure = NO;
    if ([responder respondsToSelector:@selector(isSecureTextEntry)]) {
        secure = [[responder valueForKey:@"isSecureTextEntry"] boolValue];
    }
    [[CMMonitor sharedMonitor] setSecureInputActive:secure];
}

- (UIResponder *)findFirstResponderInView:(UIView *)view {
    if (!view) {
        return nil;
    }
    if (view.isFirstResponder) {
        return view;
    }
    for (UIView *subview in view.subviews) {
        UIResponder *responder = [self findFirstResponderInView:subview];
        if (responder) {
            return responder;
        }
    }
    return nil;
}

@end
