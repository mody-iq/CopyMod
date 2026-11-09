#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

/// Root settings screen. Specifiers are built in code so the bundle does not
/// depend on a plist that could fail to load.
@interface CMRootListController : PSListController
@end
