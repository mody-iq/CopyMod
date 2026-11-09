#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One clipboard entry. Kept deliberately tiny: only text is stored.
@interface CMItem : NSObject <NSCopying>
@property(nonatomic, copy) NSString *text;
@property(nonatomic, assign) NSTimeInterval timestamp;
@property(nonatomic, copy, nullable) NSString *sourceBundleID;
@property(nonatomic, assign) BOOL pinned;

+ (instancetype)itemWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)dictionaryRepresentation;
@end

/// A single JSON file shared by every process that loads the tweak.
///
/// The file lives outside any app container so SpringBoard and each app that
/// hosts the keyboard can read it. A corrupt file is discarded and rebuilt
/// rather than crashing the host process.
@interface CMStore : NSObject

+ (instancetype)sharedStore;

/// Rootless/roothide safe absolute path of the history file.
+ (NSString *)historyPath;
+ (NSString *)exportPath;

/// YES when this process may write the shared history (SpringBoard and other
/// unsandboxed processes). Sandboxed apps only read.
+ (BOOL)canRecord;

/// Newest-first snapshot of the stored entries.
- (NSArray<CMItem *> *)items;

/// Records a copy. Duplicates are moved to the top instead of being added
/// twice. Returns YES when the stored history actually changed.
- (BOOL)recordText:(nullable NSString *)text sourceBundleID:(nullable NSString *)bundleID;

- (void)togglePinForItem:(CMItem *)item;
- (void)deleteItem:(CMItem *)item;
- (void)clearAll;

/// Writes the current history to a plain-text file and returns its path.
- (nullable NSString *)exportToTextFile;

@end
NS_ASSUME_NONNULL_END
