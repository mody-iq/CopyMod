#import "CMRootListController.h"
#import <notify.h>
#import <roothide.h>

static NSString *const kCMDomain = @"com.mody.copymod";
static NSString *const kCMHistoryDomain = @"com.mody.copymod.history";
static NSString *const kCMHistoryKey = @"history";
static NSString *const kCMNotificationPrefs = @"com.mody.copymod.prefs";
static NSString *const kCMNotificationReload = @"com.mody.copymod.reload";
static NSString *const kCMNotificationClear = @"com.mody.copymod.clear";
static NSString *const kCMNotificationExport = @"com.mody.copymod.export";

static NSString *CMLocalized(NSString *key) {
    static NSDictionary *en;
    static NSDictionary *ar;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      en = @{
          @"Enabled" : @"Enabled",
          @"Open with" : @"Open with",
          @"Keyboard button" : @"Keyboard button",
          @"Two-finger swipe up" : @"Two-finger swipe up",
          @"Button and gesture" : @"Button and gesture",
          @"Maximum items" : @"Maximum items",
          @"Ignore very long text" : @"Ignore very long text",
          @"Maximum text length" : @"Maximum text length",
          @"Ignore password fields" : @"Ignore password fields",
          @"Ignored apps" : @"Ignored apps",
          @"Clear history" : @"Clear history",
          @"Export history" : @"Export history",
          @"Delete all clipboard history?" : @"Delete all clipboard history?",
          @"History cleared" : @"History cleared",
          @"Exported to" : @"Exported to",
          @"No history to export" : @"No history to export",
          @"Export failed" : @"Export failed",
          @"Add app" : @"Add app",
          @"Bundle identifier" : @"Bundle identifier",
          @"Cancel" : @"Cancel",
          @"Add" : @"Add",
          @"None" : @"None",
      };
      ar = @{
          @"Enabled" : @"تفعيل",
          @"Open with" : @"طريقة الفتح",
          @"Keyboard button" : @"زر في الكيبورد",
          @"Two-finger swipe up" : @"سحب بإصبعين للأعلى",
          @"Button and gesture" : @"الزر والإيماءة",
          @"Maximum items" : @"أقصى عدد عناصر",
          @"Ignore very long text" : @"تجاهل النص الطويل جدا",
          @"Maximum text length" : @"أقصى طول للنص",
          @"Ignore password fields" : @"تجاهل حقول كلمات المرور",
          @"Ignored apps" : @"تطبيقات متجاهلة",
          @"Clear history" : @"حذف السجل",
          @"Export history" : @"تصدير السجل",
          @"Delete all clipboard history?" : @"حذف كل سجل النسخ؟",
          @"History cleared" : @"تم حذف السجل",
          @"Exported to" : @"تم التصدير إلى",
          @"No history to export" : @"لا يوجد سجل للتصدير",
          @"Export failed" : @"فشل التصدير",
          @"Add app" : @"إضافة تطبيق",
          @"Bundle identifier" : @"معرف الحزمة",
          @"Cancel" : @"إلغاء",
          @"Add" : @"إضافة",
          @"None" : @"لا شيء",
      };
    });
    NSString *language = [NSLocale preferredLanguages].firstObject ?: @"en";
    BOOL isArabic = [[[language componentsSeparatedByString:@"-"].firstObject lowercaseString] isEqualToString:@"ar"];
    NSDictionary *table = isArabic ? ar : en;
    return table[key] ?: key;
}

@interface CMRootListController ()
@property(nonatomic, strong) NSMutableArray<NSString *> *ignoredApps;
@end

@implementation CMRootListController

#pragma mark - Specifiers

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self buildSpecifiers] mutableCopy];
    }
    return _specifiers;
}

- (NSMutableArray *)buildSpecifiers {
    NSMutableArray *specifiers = [NSMutableArray array];

    [specifiers addObject:[PSSpecifier groupSpecifierWithName:@""]];

    PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:CMLocalized(@"Enabled")
                                                          target:self
                                                             set:@selector(setPreferenceValue:forSpecifier:)
                                                             get:@selector(readPreferenceValue:)
                                                          detail:nil
                                                            cell:PSSwitchCell
                                                            edit:nil];
    [enabled setProperty:kCMDomain forKey:@"defaults"];
    [enabled setProperty:@"enabled" forKey:@"key"];
    [enabled setProperty:@YES forKey:@"default"];
    [specifiers addObject:enabled];

    PSSpecifier *activation = [PSSpecifier preferenceSpecifierNamed:CMLocalized(@"Open with")
                                                             target:self
                                                                set:@selector(setPreferenceValue:forSpecifier:)
                                                                get:@selector(readPreferenceValue:)
                                                             detail:nil
                                                               cell:PSLinkListCell
                                                               edit:nil];
    [activation setProperty:kCMDomain forKey:@"defaults"];
    [activation setProperty:@"activation" forKey:@"key"];
    [activation setProperty:@2 forKey:@"default"];
    [activation setProperty:@[ CMLocalized(@"Keyboard button"), CMLocalized(@"Two-finger swipe up"), CMLocalized(@"Button and gesture") ]
                     forKey:@"titles"];
    [activation setProperty:@[ @1, @2, @3 ] forKey:@"values"];
    [specifiers addObject:activation];

    PSSpecifier *maxItems = [PSSpecifier preferenceSpecifierNamed:CMLocalized(@"Maximum items")
                                                           target:self
                                                              set:@selector(setPreferenceValue:forSpecifier:)
                                                              get:@selector(readPreferenceValue:)
                                                           detail:nil
                                                             cell:PSLinkListCell
                                                             edit:nil];
    [maxItems setProperty:kCMDomain forKey:@"defaults"];
    [maxItems setProperty:@"maxItems" forKey:@"key"];
    [maxItems setProperty:@200 forKey:@"default"];
    [maxItems setProperty:@[ @"50", @"100", @"200", @"500", @"1000" ] forKey:@"titles"];
    [maxItems setProperty:@[ @50, @100, @200, @500, @1000 ] forKey:@"values"];
    [specifiers addObject:maxItems];

    [specifiers addObject:[PSSpecifier groupSpecifierWithName:@""]];

    PSSpecifier *ignoreLong = [PSSpecifier preferenceSpecifierNamed:CMLocalized(@"Ignore very long text")
                                                             target:self
                                                                set:@selector(setPreferenceValue:forSpecifier:)
                                                                get:@selector(readPreferenceValue:)
                                                             detail:nil
                                                               cell:PSSwitchCell
                                                               edit:nil];
    [ignoreLong setProperty:kCMDomain forKey:@"defaults"];
    [ignoreLong setProperty:@"ignoreLongText" forKey:@"key"];
    [ignoreLong setProperty:@YES forKey:@"default"];
    [specifiers addObject:ignoreLong];

    PSSpecifier *maxLength = [PSSpecifier preferenceSpecifierNamed:CMLocalized(@"Maximum text length")
                                                            target:self
                                                               set:@selector(setPreferenceValue:forSpecifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:nil
                                                              cell:PSEditTextCell
                                                              edit:nil];
    [maxLength setProperty:kCMDomain forKey:@"defaults"];
    [maxLength setProperty:@"maxTextLength" forKey:@"key"];
    [maxLength setProperty:@5000 forKey:@"default"];
    [maxLength setProperty:@"0123456789" forKey:@"keyboardType"];
    [specifiers addObject:maxLength];

    PSSpecifier *ignoreSecure = [PSSpecifier preferenceSpecifierNamed:CMLocalized(@"Ignore password fields")
                                                               target:self
                                                                  set:@selector(setPreferenceValue:forSpecifier:)
                                                                  get:@selector(readPreferenceValue:)
                                                               detail:nil
                                                                 cell:PSSwitchCell
                                                                 edit:nil];
    [ignoreSecure setProperty:kCMDomain forKey:@"defaults"];
    [ignoreSecure setProperty:@"ignoreSecureText" forKey:@"key"];
    [ignoreSecure setProperty:@YES forKey:@"default"];
    [specifiers addObject:ignoreSecure];

    [specifiers addObject:[PSSpecifier groupSpecifierWithName:@""]];

    PSSpecifier *addApp = [PSSpecifier preferenceSpecifierNamed:CMLocalized(@"Add app")
                                                         target:self
                                                            set:nil
                                                            get:nil
                                                         detail:nil
                                                           cell:PSButtonCell
                                                           edit:nil];
    addApp.buttonAction = @selector(addIgnoredApp);
    [specifiers addObject:addApp];

    for (NSString *bundleID in self.ignoredApps) {
        PSSpecifier *app = [PSSpecifier preferenceSpecifierNamed:bundleID
                                                          target:self
                                                             set:nil
                                                             get:nil
                                                          detail:nil
                                                            cell:PSButtonCell
                                                            edit:nil];
        app.buttonAction = @selector(removeIgnoredApp:);
        [app setProperty:bundleID forKey:@"cmBundleID"];
        [specifiers addObject:app];
    }

    [specifiers addObject:[PSSpecifier groupSpecifierWithName:@""]];

    PSSpecifier *clear = [PSSpecifier preferenceSpecifierNamed:CMLocalized(@"Clear history")
                                                        target:self
                                                           set:nil
                                                           get:nil
                                                        detail:nil
                                                          cell:PSButtonCell
                                                          edit:nil];
    clear.buttonAction = @selector(clearHistory);
    [clear setProperty:@YES forKey:@"isDestructive"];
    [specifiers addObject:clear];

    PSSpecifier *export = [PSSpecifier preferenceSpecifierNamed:CMLocalized(@"Export history")
                                                         target:self
                                                            set:nil
                                                            get:nil
                                                         detail:nil
                                                           cell:PSButtonCell
                                                           edit:nil];
    export.buttonAction = @selector(exportHistory);
    [specifiers addObject:export];

    return specifiers;
}

#pragma mark - Preferences

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id fallback = [specifier propertyForKey:@"default"];
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)kCMDomain);
    return value ? (__bridge_transfer id)value : fallback;
}

- (void)setPreferenceValue:(id)value forSpecifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)kCMDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kCMDomain);
    [self broadcastPreferencesChanged];
}

- (void)broadcastPreferencesChanged {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kCMNotificationPrefs, nil, nil, YES);
}

#pragma mark - Ignored apps

- (NSMutableArray<NSString *> *)ignoredApps {
    if (!_ignoredApps) {
        CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)@"ignoredApps",
                                                            (__bridge CFStringRef)kCMDomain);
        NSArray *stored = value ? (__bridge_transfer NSArray *)value : nil;
        _ignoredApps = [stored isKindOfClass:[NSArray class]] ? [stored mutableCopy] : [NSMutableArray array];
    }
    return _ignoredApps;
}

- (void)saveIgnoredApps {
    CFPreferencesSetAppValue((__bridge CFStringRef)@"ignoredApps",
                             (__bridge CFPropertyListRef)self.ignoredApps,
                             (__bridge CFStringRef)kCMDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kCMDomain);
    [self broadcastPreferencesChanged];
}

- (void)addIgnoredApp {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:CMLocalized(@"Add app")
                                            message:CMLocalized(@"Bundle identifier")
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
      textField.placeholder = @"com.example.app";
      textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
      textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:CMLocalized(@"Cancel")
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:CMLocalized(@"Add")
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
                                             NSString *text = alert.textFields.firstObject.text;
                                             text = [text stringByTrimmingCharactersInSet:
                                                              [NSCharacterSet whitespaceCharacterSet]];
                                             if (text.length && ![weakSelf.ignoredApps containsObject:text]) {
                                                 [weakSelf.ignoredApps addObject:text];
                                                 [weakSelf saveIgnoredApps];
                                                 [weakSelf reloadSpecifiers];
                                             }
                                           }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)removeIgnoredApp:(PSSpecifier *)specifier {
    NSString *bundleID = [specifier propertyForKey:@"cmBundleID"];
    if (bundleID.length) {
        [self.ignoredApps removeObject:bundleID];
        [self saveIgnoredApps];
        [self reloadSpecifiers];
    }
}

#pragma mark - History actions

- (void)clearHistory {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"CopyMod"
                                            message:CMLocalized(@"Delete all clipboard history?")
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:CMLocalized(@"Cancel")
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:CMLocalized(@"Clear history")
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *action) {
                                             // The recording process owns the shared file; ask it to clear.
                                             CFPreferencesSetAppValue((__bridge CFStringRef)kCMHistoryKey,
                                                                      (__bridge CFPropertyListRef)@[],
                                                                      (__bridge CFStringRef)kCMHistoryDomain);
                                             CFPreferencesAppSynchronize((__bridge CFStringRef)kCMHistoryDomain);
                                             CFNotificationCenterPostNotification(
                                                 CFNotificationCenterGetDarwinNotifyCenter(),
                                                 (__bridge CFStringRef)kCMNotificationClear, nil, nil, YES);
                                             [self presentMessage:CMLocalized(@"History cleared")];
                                           }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)exportHistory {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kCMNotificationExport, nil, nil, YES);
    NSString *path = jbroot(@"/var/mobile/Library/com.mody.copymod/export.txt");
    // Give the recording process a moment to write before reporting.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                         [self presentMessage:[NSString stringWithFormat:@"%@ %@",
                                                                         CMLocalized(@"Exported to"), path]];
                     } else {
                         [self presentMessage:CMLocalized(@"No history to export")];
                     }
                   });
}

- (void)presentMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"CopyMod"
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
