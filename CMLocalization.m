#import "CMLocalization.h"

BOOL CMDeviceIsArabic(void) {
    static BOOL arabic;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      NSString *language = [NSLocale preferredLanguages].firstObject ?: @"en";
      NSString *code = [[language componentsSeparatedByString:@"-"].firstObject lowercaseString];
      arabic = [code isEqualToString:@"ar"];
    });
    return arabic;
}

NSString *CMLocalizedString(NSString *key) {
    static NSDictionary<NSString *, NSString *> *english;
    static NSDictionary<NSString *, NSString *> *arabic;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      english = @{
          @"Search" : @"Search",
          @"Space" : @"Space",
          @"Done" : @"Done",
          @"No copied text yet" : @"No copied text yet",
          @"Copy" : @"Copy",
          @"Pin" : @"Pin",
          @"Unpin" : @"Unpin",
          @"Delete" : @"Delete",
          @"Cancel" : @"Cancel",
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
      };
      arabic = @{
          @"Search" : @"بحث",
          @"Space" : @"مسافة",
          @"Done" : @"تم",
          @"No copied text yet" : @"لا يوجد نص منسوخ بعد",
          @"Copy" : @"نسخ",
          @"Pin" : @"تثبيت",
          @"Unpin" : @"إلغاء التثبيت",
          @"Delete" : @"حذف",
          @"Cancel" : @"إلغاء",
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
      };
    });

    NSDictionary *table = CMDeviceIsArabic() ? arabic : english;
    NSString *value = table[key];
    return value ?: key;
}
