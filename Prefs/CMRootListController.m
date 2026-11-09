#import "CMRootListController.h"
#import <notify.h>
#import <roothide.h>

static NSString *const kCMDomain = @"com.mody.copymod";
static NSString *const kCMHistoryDomain = @"com.mody.copymod.history";
static NSString *const kCMHistoryKey = @"history";
static NSString *const kCMNotificationPrefs = @"com.mody.copymod.prefs";
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
        _specifiers = [[self buildSpecifiers] mutableCopy] ?: [NSMutableArray array];
    }
    return _specifiers;
}

- (PSSpecifier *)switchSpecifierNamed:(NSString *)name key:(NSString *)key defaultValue:(BOOL)value {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
                                                            target:self
                                                               set:@selector(setPreferenceValue:forSpecifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:nil
                                                              cell:PSSwitchCell
                                                              edit:nil];
    [specifier setProperty:kCMDomain forKey:@"defaults"];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:@(value) forKey:@"default"];
    return specifier;
}

- (PSSpecifier *)listSpecifierNamed:(NSString *)name
                                key:(NSString *)key
                          defaultV:(NSNumber *)defaultValue
                             titles:(NSArray *)titles
                             values:(NSArray *)values {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
                                                            target:self
                                                               set:@selector(setPreferenceValue:forSpecifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:nil
                                                              cell:PSLinkListCell
                                                              edit:nil];
    [specifier setProperty:kCMDomain forKey:@"defaults"];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:defaultValue forKey:@"default"];
    [specifier setProperty:titles forKey:@"titles"];
    [specifier setProperty:values forKey:@"values"];
    return specifier;
}

- (PSSpecifier *)buttonSpecifierNamed:(NSString *)name action:(SEL)action {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
                                                            target:self
                                                               set:nil
                                                               get:nil
                                                            detail:nil
                                                              cell:PSButtonCell
                                                              edit:nil];
    specifier.buttonAction = action;
    return specifier;
}

- (NSMutableArray *)buildSpecifiers {
    NSMutableArray *specifiers = [NSMutableArray array];
    @try {
        [specifiers addObject:[PSSpecifier groupSpecifierWithName:@""]];
        [specifiers addObject:[self switchSpecifierNamed:CMLocalized(@"Enabled")
                                                    key:@"enabled"
                                           defaultValue:YES]];

        [specifiers addObject:[self listSpecifierNamed:CMLocalized(@"Open with")
                                                   key:@"activation"
                                             defaultV:@2
                                                titles:@[ CMLocalized(@"Keyboard button"),
                                                          CMLocalized(@"Two-finger swipe up"),
                                                          CMLocalized(@"Button and gesture") ]
                                                values:@[ @1, @2, @3 ]]];

        [specifiers addObject:[self listSpecifierNamed:CMLocalized(@"Maximum items")
                                                   key:@"maxItems"
                                             defaultV:@200
                                                titles:@[ @"50", @"100", @"200", @"500", @"1000" ]
                                                values:@[ @50, @100, @200, @500, @1000 ]]];

        [specifiers addObject:[PSSpecifier groupSpecifierWithName:@""]];
        [specifiers addObject:[self switchSpecifierNamed:CMLocalized(@"Ignore very long text")
                                                    key:@"ignoreLongText"
                                           defaultValue:YES]];

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
        [maxLength setProperty:@(UIKeyboardTypeNumberPad) forKey:@"keyboardType"];
        [specifiers addObject:maxLength];

        [specifiers addObject:[self switchSpecifierNamed:CMLocalized(@"Ignore password fields")
                                                    key:@"ignoreSecureText"
                                           defaultValue:YES]];

        [specifiers addObject:[PSSpecifier groupSpecifierWithName:CMLocalized(@"Ignored apps")]];
        [specifiers addObject:[self buttonSpecifierNamed:CMLocalized(@"Add app")
                                                  action:@selector(addIgnoredApp)]];
        for (NSString *bundleID in self.ignoredApps) {
            PSSpecifier *app = [self buttonSpecifierNamed:bundleID action:@selector(removeIgnoredApp:)];
            [app setProperty:bundleID forKey:@"cmBundleID"];
            [specifiers addObject:app];
        }

        [specifiers addObject:[PSSpecifier groupSpecifierWithName:@""]];
        PSSpecifier *clear = [self buttonSpecifierNamed:CMLocalized(@"Clear history")
                                                 action:@selector(clearHistory)];
        [clear setProperty:@YES forKey:@"isDestructive"];
        [specifiers addObject:clear];
        [specifiers addObject:[self buttonSpecifierNamed:CMLocalized(@"Export history")
                                                  action:@selector(exportHistory)]];
    } @catch (NSException *exception) {
        NSLog(@"[CopyMod] specifiers build failed: %@", exception.reason);
    }
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
    NSDate *requested = [NSDate date];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kCMNotificationExport, nil, nil, YES);
    NSString *path = jbroot(@"/var/mobile/Library/com.mody.copymod/export.txt");
    // Give the recording process a moment to write before reporting.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     NSDictionary *attributes =
                         [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
                     NSDate *modified = attributes[NSFileModificationDate];
                     // A stale file from an earlier export must not count as success.
                     if (modified && [modified timeIntervalSinceDate:requested] > -1.0) {
                         [self presentMessage:[NSString stringWithFormat:@"%@ %@",
                                                                         CMLocalized(@"Exported to"), path]];
                     } else if (attributes) {
                         [self presentMessage:CMLocalized(@"Export failed")];
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
