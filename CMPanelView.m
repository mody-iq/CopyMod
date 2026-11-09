#import "CMPanelView.h"
#import "CMCommon.h"
#import "CMStore.h"
#import "CMPreferences.h"
#import "CMLocalization.h"

#import <notify.h>

static NSString *const kCMCellIdentifier = @"CMHistoryCell";
static const CGFloat kCMTitleHeight = 44;
static const CGFloat kCMSearchHeight = 50;
static const CGFloat kCMKeypadHeight = 198;
static const CGFloat kCMHorizontalInset = 12;

// Ordered app windows (key window first), excluding the keyboard's own window.
static NSArray<UIWindow *> *CMAppWindows(void) {
    NSMutableArray<UIWindow *> *ordered = [NSMutableArray array];
    UIApplication *application = UIApplication.sharedApplication;
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if ([NSStringFromClass(window.class) containsString:@"KeyboardWindow"] ||
                window.hidden || window.alpha <= 0.01) {
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

@interface CMPanelView () <UITableViewDataSource, UITableViewDelegate>

@property(nonatomic, strong) UIView *header;
@property(nonatomic, strong) UIView *separator;
@property(nonatomic, strong) UIImageView *titleIcon;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UIButton *closeButton;
@property(nonatomic, strong) UIView *searchBox;
@property(nonatomic, strong) UIImageView *searchIcon;
@property(nonatomic, strong) UILabel *searchLabel;
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) UILabel *emptyLabel;
@property(nonatomic, strong) UIView *keypad;
@property(nonatomic, strong) UILabel *toastLabel;
@property(nonatomic, strong) NSArray<CMItem *> *filteredItems;
@property(nonatomic, copy) NSString *query;
@property(nonatomic, assign) BOOL keypadVisible;
@property(nonatomic, assign) CGSize lastKeypadSize;
@property(nonatomic, assign) int reloadToken;
@property(nonatomic, assign) BOOL presented;

@end

@implementation CMPanelView

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _filteredItems = @[];
        _query = @"";
        _reloadToken = -1;
        self.backgroundColor = [UIColor systemBackgroundColor];
        [self buildHeader];
        [self buildSearchBox];
        [self buildTable];
        [self buildKeypad];
        [self buildToast];
        [self registerForReload];
        [self reloadData];
    }
    return self;
}

- (void)dealloc {
    if (_reloadToken > 0) {
        notify_cancel(_reloadToken);
    }
}

- (BOOL)isRTL {
    return [UIView userInterfaceLayoutDirectionForSemanticContentAttribute:self.semanticContentAttribute] ==
           UIUserInterfaceLayoutDirectionRightToLeft;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    UIEdgeInsets safeArea = self.safeAreaInsets;
    CGFloat top = safeArea.top > 0 ? safeArea.top : 0;

    self.header.frame = CGRectMake(0, top, width, kCMTitleHeight);
    self.separator.frame = CGRectMake(0, CGRectGetMaxY(self.header.frame) - 0.5, width, 0.5);
    self.closeButton.frame = [self closeButtonFrameInWidth:width top:top];

    CGFloat titleMid = CGRectGetMidY(self.header.bounds);
    self.titleIcon.frame = CGRectMake(0, 0, 18, 18);
    CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(width, kCMTitleHeight)];
    CGFloat iconSpacing = 6;
    CGFloat groupWidth = 18 + iconSpacing + titleSize.width;
    CGFloat groupX = (width - groupWidth) / 2;
    self.titleIcon.center = CGPointMake(groupX + 9, titleMid);
    self.titleLabel.frame = CGRectMake(groupX + 18 + iconSpacing, 0, titleSize.width, kCMTitleHeight);

    CGFloat searchTop = CGRectGetMaxY(self.header.frame);
    self.searchBox.frame = CGRectMake(kCMHorizontalInset, searchTop + 7,
                                      width - kCMHorizontalInset * 2, kCMSearchHeight - 14);
    CGFloat iconSize = 16;
    BOOL rtl = [self isRTL];
    CGFloat iconX = rtl ? CGRectGetMaxX(self.searchBox.bounds) - kCMHorizontalInset - iconSize
                        : kCMHorizontalInset;
    self.searchIcon.frame = CGRectMake(iconX, (CGRectGetHeight(self.searchBox.bounds) - iconSize) / 2,
                                       iconSize, iconSize);
    CGFloat labelX = rtl ? kCMHorizontalInset : kCMHorizontalInset + iconSize + 6;
    CGFloat labelWidth = CGRectGetWidth(self.searchBox.bounds) - kCMHorizontalInset * 2 - iconSize - 6;
    self.searchLabel.frame = CGRectMake(labelX, 0, labelWidth, CGRectGetHeight(self.searchBox.bounds));
    self.searchLabel.textAlignment = rtl ? NSTextAlignmentRight : NSTextAlignmentLeft;

    CGFloat keypadHeight = self.keypadVisible ? MIN(kCMKeypadHeight, height * 0.55) : 0;
    CGFloat bottomInset = safeArea.bottom;
    self.keypad.frame = CGRectMake(0, height - keypadHeight - bottomInset, width, keypadHeight);
    if (self.keypadVisible) {
        [self layoutKeypad];
    }

    CGFloat tableTop = CGRectGetMaxY(self.searchBox.frame) + 7;
    CGFloat tableHeight = MAX(0, height - tableTop - keypadHeight - bottomInset);
    self.tableView.frame = CGRectMake(0, tableTop, width, tableHeight);
    self.emptyLabel.frame = self.tableView.frame;
    self.toastLabel.frame = CGRectMake(20, CGRectGetMaxY(self.tableView.frame) - 56, width - 40, 40);
}

- (CGRect)closeButtonFrameInWidth:(CGFloat)width top:(CGFloat)top {
    CGFloat size = 30;
    CGFloat margin = kCMHorizontalInset;
    CGFloat x = [self isRTL] ? margin : (width - size - margin);
    return CGRectMake(x, top + (kCMTitleHeight - size) / 2, size, size);
}

- (void)setPanelHeight:(CGFloat)panelHeight {
    _panelHeight = panelHeight;
    [self setNeedsLayout];
}

#pragma mark - Presentation

- (void)presentInView:(UIView *)host {
    if (!host || self.presented) {
        return;
    }
    self.presented = YES;
    self.frame = host.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.alpha = 0;
    [host addSubview:self];
    [host bringSubviewToFront:self];
    [self reloadData];
    [self setNeedsLayout];
    [UIView animateWithDuration:0.2
                     animations:^{
                       self.alpha = 1;
                     }];
}

- (void)dismiss {
    if (!self.presented) {
        return;
    }
    self.presented = NO;
    void (^handler)(void) = self.dismissHandler;
    [UIView animateWithDuration:0.15
        animations:^{
          self.alpha = 0;
        }
        completion:^(BOOL finished) {
          [self removeFromSuperview];
          if (handler) {
              handler();
          }
        }];
}

#pragma mark - UI construction

- (void)buildHeader {
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = [UIColor secondarySystemBackgroundColor];
    [self addSubview:header];
    self.header = header;

    UIView *separator = [[UIView alloc] init];
    separator.backgroundColor = [UIColor separatorColor];
    [self addSubview:separator];
    self.separator = separator;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"doc.on.clipboard"]];
    icon.tintColor = [UIColor secondaryLabelColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [header addSubview:icon];
    self.titleIcon = icon;

    UILabel *title = [[UILabel alloc] init];
    title.text = @"CopyMod";
    title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    title.textColor = [UIColor labelColor];
    [header addSubview:title];
    self.titleLabel = title;

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    closeButton.tintColor = [UIColor secondaryLabelColor];
    closeButton.backgroundColor = [UIColor tertiarySystemBackgroundColor];
    closeButton.layer.cornerRadius = 15;
    closeButton.clipsToBounds = YES;
    [closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:closeButton];
    self.closeButton = closeButton;
}

- (void)buildSearchBox {
    // A tappable container rather than a text field: the panel owns its own
    // keypad and must never raise the system keyboard on top of itself.
    UIView *searchBox = [[UIView alloc] init];
    searchBox.backgroundColor = [UIColor tertiarySystemBackgroundColor];
    searchBox.layer.cornerRadius = 10;
    searchBox.clipsToBounds = YES;
    searchBox.userInteractionEnabled = YES;
    [searchBox addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                           action:@selector(toggleKeypad)]];
    [self addSubview:searchBox];
    self.searchBox = searchBox;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]];
    icon.tintColor = [UIColor placeholderTextColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [searchBox addSubview:icon];
    self.searchIcon = icon;

    UILabel *label = [[UILabel alloc] init];
    label.text = CMLocalizedString(@"Search");
    label.textColor = [UIColor placeholderTextColor];
    label.font = [UIFont systemFontOfSize:16];
    [searchBox addSubview:label];
    self.searchLabel = label;
}

- (void)buildTable {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.backgroundColor = [UIColor clearColor];
    tableView.separatorInset = UIEdgeInsetsMake(0, 16, 0, 16);
    tableView.rowHeight = UITableViewAutomaticDimension;
    tableView.estimatedRowHeight = 52;
    tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeNone;
    [tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kCMCellIdentifier];
    [self addSubview:tableView];
    self.tableView = tableView;

    UILabel *emptyLabel = [[UILabel alloc] init];
    emptyLabel.text = CMLocalizedString(@"No copied text yet");
    emptyLabel.textColor = [UIColor secondaryLabelColor];
    emptyLabel.font = [UIFont systemFontOfSize:15];
    emptyLabel.textAlignment = NSTextAlignmentCenter;
    emptyLabel.numberOfLines = 0;
    emptyLabel.hidden = YES;
    [self addSubview:emptyLabel];
    self.emptyLabel = emptyLabel;
}

- (void)buildKeypad {
    UIView *keypad = [[UIView alloc] init];
    keypad.backgroundColor = [UIColor secondarySystemBackgroundColor];
    keypad.hidden = YES;
    keypad.clipsToBounds = YES;
    [self addSubview:keypad];
    self.keypad = keypad;
}

- (void)buildToast {
    UILabel *toast = [[UILabel alloc] init];
    toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8];
    toast.textColor = [UIColor whiteColor];
    toast.font = [UIFont systemFontOfSize:14];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.numberOfLines = 2;
    toast.layer.cornerRadius = 10;
    toast.clipsToBounds = YES;
    toast.alpha = 0;
    toast.hidden = YES;
    [self addSubview:toast];
    self.toastLabel = toast;
}

- (NSArray<NSString *> *)keypadRows {
    if (CMDeviceIsArabic()) {
        return @[ @"ضصثقفغعهخحج", @"شسيبلاتنمكط", @"ئءؤرلاىةوزظ" ];
    }
    return @[ @"qwertyuiop", @"asdfghjkl", @"zxcvbnm" ];
}

#pragma mark - Keypad layout

- (void)layoutKeypad {
    CGFloat width = CGRectGetWidth(self.keypad.bounds);
    CGFloat height = CGRectGetHeight(self.keypad.bounds);
    if (width <= 0 || height <= 0) {
        return;
    }
    if (CGSizeEqualToSize(self.lastKeypadSize, self.keypad.bounds.size)) {
        return;
    }
    self.lastKeypadSize = self.keypad.bounds.size;

    for (UIView *subview in self.keypad.subviews.copy) {
        [subview removeFromSuperview];
    }

    BOOL rtl = CMDeviceIsArabic();
    NSArray<NSString *> *rows = [self keypadRows];
    NSUInteger rowCount = rows.count + 1;
    CGFloat pad = 3;
    CGFloat rowHeight = (height - pad * (CGFloat)(rowCount + 1)) / (CGFloat)rowCount;

    for (NSUInteger r = 0; r < rows.count; r++) {
        NSString *letters = rows[r];
        NSUInteger count = letters.length;
        CGFloat keyWidth = (width - pad * (CGFloat)(count + 1)) / (CGFloat)count;
        for (NSUInteger c = 0; c < count; c++) {
            NSString *title = [letters substringWithRange:NSMakeRange(c, 1)];
            NSUInteger position = rtl ? (count - 1 - c) : c;
            CGRect frame = CGRectMake(pad + (CGFloat)position * (keyWidth + pad),
                                      pad + (CGFloat)r * (rowHeight + pad), keyWidth, rowHeight);
            [self.keypad addSubview:[self keyButtonWithTitle:title
                                                       frame:frame
                                                      action:@selector(keyTapped:)]];
        }
    }

    // Utility row: space, delete, done.
    CGFloat y = pad + (CGFloat)rows.count * (rowHeight + pad);
    CGFloat spaceWidth = width * 0.52;
    CGFloat deleteWidth = width * 0.20;
    CGFloat doneWidth = width - spaceWidth - deleteWidth - pad * 4;
    BOOL arabic = CMDeviceIsArabic();

    CGFloat x = pad;
    UIButton *space = [self keyButtonWithTitle:CMLocalizedString(@"Space")
                                         frame:CGRectMake(x, y, spaceWidth, rowHeight)
                                        action:@selector(spaceTapped)];
    [self.keypad addSubview:space];

    x += spaceWidth + pad;
    UIButton *delete = [self keyButtonWithTitle:@"⌫"
                                          frame:CGRectMake(x, y, deleteWidth, rowHeight)
                                         action:@selector(deleteTapped)];
    [self.keypad addSubview:delete];

    x += deleteWidth + pad;
    UIButton *done = [self keyButtonWithTitle:CMLocalizedString(@"Done")
                                        frame:CGRectMake(x, y, doneWidth, rowHeight)
                                       action:@selector(doneTapped)];
    done.backgroundColor = [UIColor systemBlueColor];
    [done setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.keypad addSubview:done];

    (void)arabic;
}

- (UIButton *)keyButtonWithTitle:(NSString *)title frame:(CGRect)frame action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = frame;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:19 weight:UIFontWeightRegular];
    button.backgroundColor = [UIColor systemBackgroundColor];
    button.layer.cornerRadius = 6;
    button.clipsToBounds = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

#pragma mark - Keypad actions

- (void)toggleKeypad {
    self.keypadVisible = !self.keypadVisible;
    self.keypad.hidden = !self.keypadVisible;
    self.lastKeypadSize = CGSizeZero;
    if (self.keypadVisible) {
        [self layoutKeypad];
    }
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

- (void)keyTapped:(UIButton *)sender {
    [self appendQuery:sender.titleLabel.text ?: @""];
}

- (void)spaceTapped {
    [self appendQuery:@" "];
}

- (void)deleteTapped {
    if (self.query.length == 0) {
        return;
    }
    [self updateQuery:[self.query substringToIndex:self.query.length - 1]];
}

- (void)doneTapped {
    if (self.keypadVisible) {
        [self toggleKeypad];
    }
}

- (void)appendQuery:(NSString *)fragment {
    [self updateQuery:[self.query stringByAppendingString:fragment]];
}

- (void)updateQuery:(NSString *)query {
    self.query = query;
    if (query.length) {
        self.searchLabel.text = query;
        self.searchLabel.textColor = [UIColor labelColor];
        self.searchIcon.image = [UIImage systemImageNamed:@"magnifyingglass"];
    } else {
        self.searchLabel.text = CMLocalizedString(@"Search");
        self.searchLabel.textColor = [UIColor placeholderTextColor];
    }
    [self reloadData];
}

#pragma mark - Reload

- (void)registerForReload {
    __weak typeof(self) weakSelf = self;
    int token = 0;
    notify_register_dispatch(kCMNotificationReload.UTF8String, &token,
                             dispatch_get_main_queue(), ^(int t) {
                               [weakSelf reloadData];
                             });
    self.reloadToken = token;
}

- (void)reloadData {
    NSArray<CMItem *> *all = [[CMStore sharedStore] items];
    NSString *query = self.query;
    if (query.length) {
        NSMutableArray *filtered = [NSMutableArray array];
        for (CMItem *item in all) {
            if ([item.text rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [filtered addObject:item];
            }
        }
        self.filteredItems = filtered;
    } else {
        self.filteredItems = all;
    }
    [self.tableView reloadData];
    self.emptyLabel.hidden = self.filteredItems.count > 0;
}

#pragma mark - Actions

- (void)closeTapped {
    [self dismiss];
}

- (void)insertText:(NSString *)text {
    id<CMPanelTextInputProvider> provider = self.inputProvider;
    BOOL inserted = provider ? [provider cm_insertText:text] : NO;
    if (inserted) {
        [self dismiss];
    } else {
        [self showToast:CMLocalizedString(@"Copied to clipboard")];
    }
}

- (void)showToast:(NSString *)message {
    self.toastLabel.text = message;
    self.toastLabel.hidden = NO;
    [UIView animateWithDuration:0.2
                     animations:^{
                       self.toastLabel.alpha = 1;
                     }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     [UIView animateWithDuration:0.3
                         animations:^{
                           self.toastLabel.alpha = 0;
                         }
                         completion:^(BOOL finished) {
                           self.toastLabel.hidden = YES;
                         }];
                   });
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.filteredItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCMCellIdentifier forIndexPath:indexPath];
    CMItem *item = self.filteredItems[(NSUInteger)indexPath.row];

    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = item.text;
    content.textProperties.numberOfLines = 2;
    content.textProperties.lineBreakMode = NSLineBreakByTruncatingTail;
    content.textProperties.font = [UIFont systemFontOfSize:16];
    if (item.pinned) {
        content.image = [UIImage systemImageNamed:@"pin.fill"];
        content.imageProperties.tintColor = [UIColor systemOrangeColor];
    }
    cell.contentConfiguration = content;
    cell.backgroundColor = [UIColor clearColor];

    // Rebuild the gesture each time so reconfiguration cannot stack duplicates.
    for (UIGestureRecognizer *recognizer in cell.gestureRecognizers.copy) {
        [cell removeGestureRecognizer:recognizer];
    }
    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [cell addGestureRecognizer:longPress];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CMItem *item = self.filteredItems[(NSUInteger)indexPath.row];
    [self insertText:item.text];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    UITableViewCell *cell = (UITableViewCell *)gesture.view;
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    if (!indexPath) {
        return;
    }
    CMItem *item = self.filteredItems[(NSUInteger)indexPath.row];

    UIAlertController *sheet =
        [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:CMLocalizedString(@"Copy")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                              [UIPasteboard generalPasteboard].string = item.text;
                                              [self showToast:CMLocalizedString(@"Copied to clipboard")];
                                            }]];
    NSString *pinTitle = item.pinned ? CMLocalizedString(@"Unpin") : CMLocalizedString(@"Pin");
    [sheet addAction:[UIAlertAction actionWithTitle:pinTitle
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                              [[CMStore sharedStore] togglePinForItem:item];
                                              [self reloadData];
                                            }]];
    [sheet addAction:[UIAlertAction actionWithTitle:CMLocalizedString(@"Delete")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
                                              [[CMStore sharedStore] deleteItem:item];
                                              [self reloadData];
                                            }]];
    [sheet addAction:[UIAlertAction actionWithTitle:CMLocalizedString(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    sheet.popoverPresentationController.sourceView = cell;
    sheet.popoverPresentationController.sourceRect = cell.bounds;

    UIViewController *presenter = [self topViewController];
    if (presenter) {
        [presenter presentViewController:sheet animated:YES completion:nil];
    }
}

- (UIViewController *)topViewController {
    // The panel lives in the keyboard window, whose root view controller may be
    // nil. Prefer a normal app window so the action sheet has a real presenter.
    UIViewController *controller = nil;
    for (UIWindow *window in CMAppWindows()) {
        if (window.rootViewController) {
            controller = window.rootViewController;
            break;
        }
    }
    if (!controller) {
        controller = self.window.rootViewController;
    }
    while (controller.presentedViewController) {
        controller = controller.presentedViewController;
    }
    return controller;
}

@end
