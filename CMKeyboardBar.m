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
- (id)asynchronousInputDelegate;
- (id)delegate;
- (void)insertText:(NSString *)text;
@end

static const CGFloat kCMButtonSize = 34;
static const CGFloat kCMButtonInset = 6;
static NSString *const kCMButtonAccessibilityLabel = @"Clipboard history";

@interface CMKeyboardBar () <UIGestureRecognizerDelegate>
@property(nonatomic, weak, readwrite, nullable) UIView *hostView;
@property(nonatomic, strong, nullable) UIButton *button;
@property(nonatomic, strong, nullable) UISwipeGestureRecognizer *swipe;
@property(nonatomic, strong, nullable) CMPanelView *panel;
@property(nonatomic, assign) BOOL presenting;
@end

@implementation CMKeyboardBar

#pragma mark - Attach / detach

- (BOOL)attachToHostView:(UIView *)hostView {
    if (!hostView) {
        return NO;
    }
    // Every UIInputSetHostView in the window calls in on each layout pass; the
    // target is resolved once and only re-resolved when a taller host view
    // appears, so the keyboard's hot layout path stays cheap.
    UIView *target = [self resolveTargetForHostView:hostView];
    if (!target) {
        return NO;
    }
    self.hostView = target;

    CMActivation activation = [CMPreferences activation];
    if (activation & CMActivationButton) {
        [self installButtonInHostView:target];
    } else if (self.button) {
        [self.button removeFromSuperview];
        self.button = nil;
    }
    if (activation & CMActivationGesture) {
        [self installGestureInHostView:target];
    } else if (self.swipe) {
        [self.swipe.view removeGestureRecognizer:self.swipe];
        self.swipe = nil;
    }

    if (self.panel && self.panel.superview == target) {
        [target bringSubviewToFront:self.panel];
    }
    return YES;
}

- (UIView *)resolveTargetForHostView:(UIView *)hostView {
    UIView *cached = self.hostView;
    if (cached && cached.window) {
        CGFloat cachedHeight = CGRectGetHeight(cached.bounds);
        if (hostView == cached || CGRectGetHeight(hostView.bounds) <= cachedHeight) {
            return cached;
        }
    }
    return [self preferredHostViewFor:hostView];
}

- (void)detach {
    [self.button removeFromSuperview];
    self.button = nil;
    if (self.swipe) {
        [self.swipe.view removeGestureRecognizer:self.swipe];
        self.swipe = nil;
    }
    [self.panel dismiss];
    self.hostView = nil;
}

- (void)refreshButton {
    if (self.button && self.hostView) {
        [self layoutButtonForHostView:self.hostView];
    }
}

// The keyboard builds several UIInputSetHostView instances (letters, numbers,
// emoji, ...). Only the tallest one is on screen, so pin the bar to that one.
- (UIView *)preferredHostViewFor:(UIView *)hostView {
    UIWindow *window = hostView.window;
    if (!window) {
        return hostView;
    }
    UIView *best = nil;
    CGFloat bestHeight = 0;
    for (UIView *candidate in [self descendantsOfView:window]) {
        if (![NSStringFromClass(candidate.class) containsString:@"UIInputSetHostView"]) {
            continue;
        }
        CGFloat height = CGRectGetHeight(candidate.bounds);
        if (height > bestHeight) {
            bestHeight = height;
            best = candidate;
        }
    }
    return best ?: hostView;
}

- (NSArray<UIView *> *)descendantsOfView:(UIView *)view {
    NSMutableArray<UIView *> *all = [NSMutableArray array];
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:view];
    while (stack.count) {
        UIView *current = stack.lastObject;
        [stack removeLastObject];
        [all addObject:current];
        [stack addObjectsFromArray:current.subviews];
    }
    return all;
}

#pragma mark - Button

- (void)installButtonInHostView:(UIView *)hostView {
    if (self.button && self.button.superview == hostView) {
        [self layoutButtonForHostView:hostView];
        [hostView bringSubviewToFront:self.button];
        return;
    }
    [self.button removeFromSuperview];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.accessibilityLabel = kCMButtonAccessibilityLabel;
    button.tintColor = [UIColor labelColor];
    button.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.14];
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
    if (self.swipe && self.swipe.view == hostView) {
        return;
    }
    if (self.swipe) {
        [self.swipe.view removeGestureRecognizer:self.swipe];
    }
    UISwipeGestureRecognizer *swipe =
        [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
    swipe.numberOfTouchesRequired = 2;
    swipe.direction = UISwipeGestureRecognizerDirectionUp;
    // Do not swallow key touches; only claim the two-finger swipe.
    swipe.cancelsTouchesInView = NO;
    swipe.delaysTouchesBegan = NO;
    swipe.delaysTouchesEnded = NO;
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
    if (self.panel && self.panel.superview) {
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

- (NSArray<UIWindow *> *)appWindows {
    NSMutableArray<UIWindow *> *ordered = [NSMutableArray array];
    UIApplication *application = UIApplication.sharedApplication;
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if ([self windowIsKeyboardWindow:window] || window.hidden || window.alpha <= 0.01) {
                continue;
            }
            if (window.isKeyWindow) {
                [ordered insertObject:window atIndex:0];
            } else {
                [ordered addObject:window];
            }
        }
    }
    return ordered;
}

- (BOOL)windowIsKeyboardWindow:(UIWindow *)window {
    return [NSStringFromClass(window.class) containsString:@"KeyboardWindow"];
}

#pragma mark - CMPanelTextInputProvider

- (BOOL)cm_insertText:(NSString *)text {
    if (![text isKindOfClass:[NSString class]] || text.length == 0) {
        return NO;
    }
    id<UIKeyInput> input = [self resolveTextInput];
    if (input) {
        @try {
            [input insertText:text];
            [self updateSecureStateFromResponder:input];
            return YES;
        } @catch (NSException *exception) {
            CM_LOG(@"insertText failed: %@", exception.reason);
        }
    }

    // Last resort: leave the text on the clipboard so the user can paste it.
    @try {
        [UIPasteboard generalPasteboard].string = text;
    } @catch (__unused NSException *exception) {
    }
    return NO;
}

- (id<UIKeyInput>)resolveTextInput {
    // 1. The focused field is the app's current first responder. This is the
    //    exact object the keyboard types into, so it is tried first.
    for (UIWindow *window in [self appWindows]) {
        UIResponder *responder = [self firstResponderInView:window];
        if ([self isTextInput:responder]) {
            return (id<UIKeyInput>)responder;
        }
    }

    // 2. Fall back to the active keyboard: its input delegate is the text input
    //    object the keyboard forwards keystrokes to.
    @try {
        Class impl = NSClassFromString(@"UIKeyboardImpl");
        id keyboard = [impl respondsToSelector:@selector(activeInstance)]
                          ? [impl performSelector:@selector(activeInstance)]
                          : nil;
        if (keyboard) {
            id candidate = nil;
            if ([keyboard respondsToSelector:@selector(inputDelegate)]) {
                candidate = [keyboard inputDelegate];
            }
            if (![self isTextInput:candidate] &&
                [keyboard respondsToSelector:@selector(asynchronousInputDelegate)]) {
                candidate = [keyboard asynchronousInputDelegate];
            }
            if (![self isTextInput:candidate] && [keyboard respondsToSelector:@selector(delegate)]) {
                candidate = [keyboard delegate];
            }
            if ([self isTextInput:candidate]) {
                return candidate;
            }
            // UIKeyboardImpl itself accepts insertText: and forwards it to the
            // focused field, which is a reliable last resort.
            if ([keyboard respondsToSelector:@selector(insertText:)]) {
                return keyboard;
            }
        }
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

- (BOOL)isTextInput:(id)candidate {
    return candidate && [candidate conformsToProtocol:@protocol(UIKeyInput)] &&
           [candidate respondsToSelector:@selector(insertText:)];
}

- (void)updateSecureStateFromResponder:(id)responder {
    BOOL secure = NO;
    if ([responder respondsToSelector:@selector(isSecureTextEntry)]) {
        secure = [[responder valueForKey:@"isSecureTextEntry"] boolValue];
    }
    [[CMMonitor sharedMonitor] setSecureInputActive:secure];
}

- (UIResponder *)firstResponderInView:(UIView *)view {
    if (!view) {
        return nil;
    }
    if (view.isFirstResponder) {
        return view;
    }
    for (UIView *subview in view.subviews) {
        UIResponder *responder = [self firstResponderInView:subview];
        if (responder) {
            return responder;
        }
    }
    return nil;
}

@end
