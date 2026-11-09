#import "CMPanelView.h"
#import "CMCommon.h"
#import "CMStore.h"
#import "CMPreferences.h"
#import "CMLocalization.h"

#import <notify.h>

static NSString *const kCMCellIdentifier = @"CMHistoryCell";
static const CGFloat kCMHeaderHeight = 52;
static const CGFloat kCMKeypadHeight = 214;

@interface CMPanelView () <UITableViewDataSource, UITableViewDelegate>

@property(nonatomic, strong) UIView *container;
@property(nonatomic, strong) UIButton *closeButton;
@property(nonatomic, strong) UILabel *searchBox;
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) UILabel *emptyLabel;
@property(nonatomic, strong) UIView *keypad;
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
        [self buildContainer];
        [self buildHeader];
        [self buildTable];
        [self buildKeypad];
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

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat panelHeight = self.panelHeight > 0 ? self.panelHeight : 300;
    panelHeight = MIN(panelHeight, CGRectGetHeight(bounds));
    self.container.frame = CGRectMake(0, CGRectGetHeight(bounds) - panelHeight,
                                      CGRectGetWidth(bounds), panelHeight);

    CGRect containerBounds = self.container.bounds;
    CGFloat width = CGRectGetWidth(containerBounds);
    self.closeButton.frame = CGRectMake(12, (kCMHeaderHeight - 32) / 2, 32, 32);
    CGFloat searchX = CGRectGetMaxX(self.closeButton.frame) + 6;
    self.searchBox.frame = CGRectMake(searchX, (kCMHeaderHeight - 36) / 2,
                                      MAX(60, width - searchX - 12), 36);

    CGFloat keypadHeight = self.keypadVisible ? MIN(kCMKeypadHeight, panelHeight * 0.6) : 0;
    self.keypad.frame = CGRectMake(0, CGRectGetHeight(containerBounds) - keypadHeight,
                                   width, keypadHeight);
    if (self.keypadVisible) {
        [self layoutKeypad];
    }

    CGFloat tableTop = kCMHeaderHeight;
    CGFloat tableHeight = MAX(0, CGRectGetHeight(containerBounds) - tableTop - keypadHeight);
    self.tableView.frame = CGRectMake(0, tableTop, width, tableHeight);
    self.emptyLabel.frame = self.tableView.frame;
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

- (void)buildContainer {
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
    UIView *container = [[UIView alloc] init];
    container.backgroundColor = [UIColor secondarySystemBackgroundColor];
    container.layer.cornerRadius = 12;
    container.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    container.clipsToBounds = YES;
    [self addSubview:container];
    self.container = container;
}

- (void)buildHeader {
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    closeButton.tintColor = [UIColor secondaryLabelColor];
    [closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.container addSubview:closeButton];
    self.closeButton = closeButton;

    // A plain label rather than a text field: the panel owns its own keypad and
    // must never raise the system keyboard on top of itself.
    UILabel *searchBox = [[UILabel alloc] init];
    searchBox.text = CMLocalizedString(@"Search");
    searchBox.textColor = [UIColor placeholderTextColor];
    searchBox.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    searchBox.backgroundColor = [UIColor tertiarySystemBackgroundColor];
    searchBox.layer.cornerRadius = 8;
    searchBox.clipsToBounds = YES;
    searchBox.userInteractionEnabled = YES;
    searchBox.textAlignment = NSTextAlignmentNatural;
    [searchBox addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                           action:@selector(toggleKeypad)]];
    [self.container addSubview:searchBox];
    self.searchBox = searchBox;
}

- (void)buildTable {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.backgroundColor = [UIColor clearColor];
    tableView.separatorInset = UIEdgeInsetsMake(0, 16, 0, 16);
    tableView.rowHeight = UITableViewAutomaticDimension;
    tableView.estimatedRowHeight = 52;
    [tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kCMCellIdentifier];
    [self.container addSubview:tableView];
    self.tableView = tableView;

    UILabel *emptyLabel = [[UILabel alloc] init];
    emptyLabel.text = CMLocalizedString(@"No copied text yet");
    emptyLabel.textColor = [UIColor secondaryLabelColor];
    emptyLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    emptyLabel.textAlignment = NSTextAlignmentCenter;
    emptyLabel.numberOfLines = 0;
    emptyLabel.hidden = YES;
    [self.container addSubview:emptyLabel];
    self.emptyLabel = emptyLabel;
}

- (void)buildKeypad {
    UIView *keypad = [[UIView alloc] init];
    keypad.backgroundColor = [UIColor tertiarySystemBackgroundColor];
    keypad.hidden = YES;
    keypad.clipsToBounds = YES;
    [self.container addSubview:keypad];
    self.keypad = keypad;
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
    // Rebuilding only when the size changed avoids churn on every layout pass.
    if (CGSizeEqualToSize(self.lastKeypadSize, self.keypad.bounds.size)) {
        return;
    }
    self.lastKeypadSize = self.keypad.bounds.size;

    for (UIView *subview in self.keypad.subviews.copy) {
        [subview removeFromSuperview];
    }

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
            CGRect frame = CGRectMake(pad + (CGFloat)c * (keyWidth + pad),
                                      pad + (CGFloat)r * (rowHeight + pad), keyWidth, rowHeight);
            [self.keypad addSubview:[self keyButtonWithTitle:title
                                                       frame:frame
                                                      action:@selector(keyTapped:)]];
        }
    }

    // Utility row: space, delete, done.
    CGFloat y = pad + (CGFloat)rows.count * (rowHeight + pad);
    CGFloat spaceWidth = width * 0.55;
    CGFloat deleteWidth = width * 0.22;
    CGFloat doneWidth = width - spaceWidth - deleteWidth - pad * 4;

    UIButton *space = [self keyButtonWithTitle:CMLocalizedString(@"Space")
                                         frame:CGRectMake(pad, y, spaceWidth, rowHeight)
                                        action:@selector(spaceTapped)];
    [self.keypad addSubview:space];

    UIButton *delete = [self keyButtonWithTitle:@"⌫"
                                          frame:CGRectMake(pad * 2 + spaceWidth, y, deleteWidth, rowHeight)
                                         action:@selector(deleteTapped)];
    [self.keypad addSubview:delete];

    UIButton *done = [self keyButtonWithTitle:CMLocalizedString(@"Done")
                                        frame:CGRectMake(pad * 3 + spaceWidth + deleteWidth, y, doneWidth, rowHeight)
                                       action:@selector(doneTapped)];
    [self.keypad addSubview:done];
}

- (UIButton *)keyButtonWithTitle:(NSString *)title frame:(CGRect)frame action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = frame;
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightRegular];
    button.backgroundColor = [UIColor systemBackgroundColor];
    button.layer.cornerRadius = 5;
    button.clipsToBounds = YES;
    button.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

#pragma mark - Keypad actions

- (void)toggleKeypad {
    self.keypadVisible = !self.keypadVisible;
    self.keypad.hidden = !self.keypadVisible;
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
    NSString *updated = [self.query substringToIndex:self.query.length - 1];
    [self updateQuery:updated];
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
    self.searchBox.text = query.length ? query : CMLocalizedString(@"Search");
    self.searchBox.textColor = query.length ? [UIColor labelColor] : [UIColor placeholderTextColor];
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
    id<UIKeyInput> input = [self.inputProvider cm_currentTextInput];
    if (input && [input respondsToSelector:@selector(insertText:)]) {
        [input insertText:text];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.filteredItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCMCellIdentifier forIndexPath:indexPath];
    CMItem *item = self.filteredItems[(NSUInteger)indexPath.row];

    UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
    content.text = item.text;
    content.textProperties.numberOfLines = 2;
    content.textProperties.lineBreakMode = NSLineBreakByTruncatingTail;
    content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
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
    [self dismiss];
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

    // Required on iPad and harmless on iPhone.
    sheet.popoverPresentationController.sourceView = cell;
    sheet.popoverPresentationController.sourceRect = cell.bounds;

    UIViewController *presenter = [self topViewController];
    if (presenter) {
        [presenter presentViewController:sheet animated:YES completion:nil];
    }
}

- (UIViewController *)topViewController {
    UIWindow *window = self.window;
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController) {
        controller = controller.presentedViewController;
    }
    return controller;
}

@end
