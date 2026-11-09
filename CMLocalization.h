#ifndef CMLOCALIZATION_H
#define CMLOCALIZATION_H

#import <Foundation/Foundation.h>

/// Returns the localized string for a key, following the device language.
///
/// The table is compiled in on purpose: the tweak runs inside arbitrary host
/// apps, where looking up a bundle-relative .strings file is unreliable.
NSString *CMLocalizedString(NSString *key);

/// YES when the device's preferred language is Arabic.
BOOL CMDeviceIsArabic(void);

#endif /* CMLOCALIZATION_H */
