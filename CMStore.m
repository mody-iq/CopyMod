#import "CMStore.h"
#import "CMCommon.h"
#import "CMPreferences.h"

#import <roothide.h>
#import <sys/stat.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>

@implementation CMItem

+ (instancetype)itemWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *text = dictionary[@"text"];
    if (![text isKindOfClass:[NSString class]] || text.length == 0) {
        return nil;
    }
    CMItem *item = [[CMItem alloc] init];
    item.text = text;
    id timestamp = dictionary[@"timestamp"];
    item.timestamp = [timestamp isKindOfClass:[NSNumber class]] ? [timestamp doubleValue] : 0;
    id bundle = dictionary[@"sourceBundleID"];
    item.sourceBundleID = [bundle isKindOfClass:[NSString class]] ? bundle : nil;
    id pinned = dictionary[@"pinned"];
    item.pinned = [pinned isKindOfClass:[NSNumber class]] ? [pinned boolValue] : NO;
    return item;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    dictionary[@"text"] = self.text ?: @"";
    dictionary[@"timestamp"] = @(self.timestamp);
    dictionary[@"pinned"] = @(self.pinned);
    if (self.sourceBundleID.length) {
        dictionary[@"sourceBundleID"] = self.sourceBundleID;
    }
    return dictionary;
}

- (id)copyWithZone:(NSZone *)zone {
    CMItem *copy = [[CMItem allocWithZone:zone] init];
    copy.text = self.text;
    copy.timestamp = self.timestamp;
    copy.sourceBundleID = self.sourceBundleID;
    copy.pinned = self.pinned;
    return copy;
}

@end

@implementation CMStore {
    NSMutableArray<CMItem *> *_items;
    dispatch_queue_t _queue;
    BOOL _writable;
}

#pragma mark - Paths

+ (NSString *)historyDirectory {
    return jbroot(@"/var/mobile/Library/com.mody.copymod");
}

+ (NSString *)historyPath {
    return [[self historyDirectory] stringByAppendingPathComponent:@"history.json"];
}

+ (NSString *)exportPath {
    return [[self historyDirectory] stringByAppendingPathComponent:@"export.txt"];
}

+ (BOOL)canRecord {
    // Only processes that can reach the shared directory record copies; every
    // other process just reads the published history. The directory is created
    // on demand so the first process able to write it becomes a recorder.
    NSString *ownBundle = [NSBundle mainBundle].bundleIdentifier;
    if ([ownBundle isEqualToString:@"com.apple.springboard"]) {
        return YES;
    }
    // Sandboxed apps never gain write access, so probe once instead of on
    // every poll tick.
    static BOOL checked = NO;
    static BOOL writable = NO;
    if (checked) {
        return writable;
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *directory = [self historyDirectory];
    if (![fileManager fileExistsAtPath:directory]) {
        [fileManager createDirectoryAtPath:directory
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:NULL];
        chmod([directory fileSystemRepresentation], 0755);
    }
    writable = [fileManager isWritableFileAtPath:directory];
    checked = YES;
    return writable;
}

#pragma mark - Lifecycle

+ (instancetype)sharedStore {
    static CMStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      store = [[CMStore alloc] init];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _items = [NSMutableArray array];
        _queue = dispatch_queue_create("com.mody.copymod.store", DISPATCH_QUEUE_SERIAL);
        _writable = [self ensureDirectory];
        [self loadLocked];
    }
    return self;
}

- (BOOL)ensureDirectory {
    @try {
        NSString *directory = [CMStore historyDirectory];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:directory]) {
            [fileManager createDirectoryAtPath:directory
                   withIntermediateDirectories:YES
                                    attributes:nil
                                         error:NULL];
        }
        BOOL isDirectory = NO;
        BOOL exists = [fileManager fileExistsAtPath:directory isDirectory:&isDirectory];
        if (exists && isDirectory) {
            chmod([directory fileSystemRepresentation], 0755);
            return YES;
        }
    } @catch (NSException *exception) {
        CM_LOG(@"ensureDirectory failed: %@", exception.reason);
    }
    return NO;
}

#pragma mark - Cross-process channel

// Guards the shared history file so two processes never interleave a
// read-modify-write. The lock is advisory and best-effort: a failure to take it
// must never break the caller, so it is used only when it can be opened.
- (int)acquireFileLock {
    if (!_writable) {
        return -1;
    }
    NSString *lockPath = [[CMStore historyPath] stringByAppendingString:@".lock"];
    int fd = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0644);
    if (fd < 0) {
        return -1;
    }
    if (flock(fd, LOCK_EX) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

- (void)releaseFileLock:(int)fd {
    if (fd < 0) {
        return;
    }
    flock(fd, LOCK_UN);
    close(fd);
}

- (NSArray *)historyArrayFromPreferences {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)kCMHistoryKey,
                                                        (__bridge CFStringRef)kCMHistoryDomain);
    NSArray *array = (value && CFGetTypeID(value) == CFArrayGetTypeID())
                         ? (__bridge_transfer NSArray *)value
                         : nil;
    return array;
}

- (void)writeHistoryArrayToPreferences:(NSArray *)array {
    CFPreferencesSetAppValue((__bridge CFStringRef)kCMHistoryKey, (__bridge CFPropertyListRef)array,
                             (__bridge CFStringRef)kCMHistoryDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kCMHistoryDomain);
}

- (NSArray *)historyArrayFromFile {
    NSData *data = [NSData dataWithContentsOfFile:[CMStore historyPath]];
    if (!data) {
        return nil;
    }
    NSError *error = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![parsed isKindOfClass:[NSArray class]]) {
        // Corrupt file: discard instead of crashing the host process.
        CM_LOG(@"history file unreadable, resetting (%@)", error.localizedDescription);
        [[NSFileManager defaultManager] removeItemAtPath:[CMStore historyPath] error:NULL];
        return nil;
    }
    return parsed;
}

#pragma mark - Load / Save

- (void)loadLocked {
    // The JSON file under the jbroot is authoritative: on rootless/roothide the
    // sandbox lets every injected process read it. CFPreferences is only a
    // fallback for the rare case where the file is out of reach.
    NSArray *array = [self historyArrayFromFile];
    if (!array) {
        array = [self historyArrayFromPreferences];
    }

    NSMutableArray<CMItem *> *loaded = [NSMutableArray array];
    for (id entry in array) {
        CMItem *item = [CMItem itemWithDictionary:entry];
        if (item) {
            [loaded addObject:item];
        }
    }
    _items = loaded;
}

- (void)saveLocked {
    NSMutableArray *serialized = [NSMutableArray arrayWithCapacity:_items.count];
    for (CMItem *item in _items) {
        [serialized addObject:[item dictionaryRepresentation]];
    }

    // Publish through the preferences channel so every process sees the change.
    [self writeHistoryArrayToPreferences:serialized];

    if (!_writable) {
        return;
    }

    NSData *data = nil;
    @try {
        data = [NSJSONSerialization dataWithJSONObject:serialized options:0 error:NULL];
    } @catch (NSException *exception) {
        CM_LOG(@"serialize failed: %@", exception.reason);
        return;
    }
    if (!data) {
        return;
    }

    NSString *path = [CMStore historyPath];
    NSString *temporary = [path stringByAppendingString:@".tmp"];
    if (![data writeToFile:temporary atomically:YES]) {
        return;
    }
    // rename() replaces the target atomically; a remove-then-move would leave
    // a window where concurrent readers see no history file at all.
    if (rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation) != 0) {
        [[NSFileManager defaultManager] removeItemAtPath:temporary error:NULL];
        return;
    }
    chmod([path fileSystemRepresentation], 0644);
}

- (NSArray<CMItem *> *)items {
    __block NSArray<CMItem *> *snapshot = nil;
    dispatch_sync(_queue, ^{
      [self loadLocked];
      NSArray<CMItem *> *sorted = [self->_items sortedArrayUsingComparator:^NSComparisonResult(CMItem *a, CMItem *b) {
        if (a.pinned != b.pinned) {
            return a.pinned ? NSOrderedAscending : NSOrderedDescending;
        }
        return a.timestamp > b.timestamp ? NSOrderedAscending : NSOrderedDescending;
      }];
      snapshot = sorted;
    });
    return snapshot ?: @[];
}

#pragma mark - Mutations

- (BOOL)recordText:(NSString *)text sourceBundleID:(NSString *)bundleID {
    if (![text isKindOfClass:[NSString class]] || text.length == 0) {
        return NO;
    }

    __block BOOL changed = NO;
    dispatch_sync(_queue, ^{
      int lock = [self acquireFileLock];
      [self loadLocked];

      CMItem *existing = nil;
      for (CMItem *item in self->_items) {
        if ([item.text isEqualToString:text]) {
            existing = item;
            break;
        }
      }

      if (existing) {
        existing.timestamp = [NSDate date].timeIntervalSince1970;
        if (bundleID.length) {
            existing.sourceBundleID = bundleID;
        }
      } else {
        CMItem *item = [[CMItem alloc] init];
        item.text = text;
        item.timestamp = [NSDate date].timeIntervalSince1970;
        item.sourceBundleID = bundleID.length ? bundleID : nil;
        [self->_items insertObject:item atIndex:0];
      }

      [self trimToLimitLocked];
      [self saveLocked];
      [self releaseFileLock:lock];
      changed = YES;
    });
    return changed;
}

- (void)trimToLimitLocked {
    NSUInteger limit = (NSUInteger)[CMPreferences maxItems];
    if (limit == 0) {
        limit = 200;
    }
    if (_items.count <= limit) {
        return;
    }

    NSMutableArray<CMItem *> *unpinned = [NSMutableArray array];
    for (CMItem *item in _items) {
        if (!item.pinned) {
            [unpinned addObject:item];
        }
    }
    NSInteger excess = (NSInteger)_items.count - (NSInteger)limit;
    while (excess > 0 && unpinned.count > 0) {
        CMItem *oldest = unpinned.lastObject;
        [_items removeObjectIdenticalTo:oldest];
        [unpinned removeLastObject];
        excess--;
    }
}

- (void)togglePinForItem:(CMItem *)item {
    if (!item) {
        return;
    }
    NSString *text = item.text;
    dispatch_sync(_queue, ^{
      int lock = [self acquireFileLock];
      [self loadLocked];
      for (CMItem *candidate in self->_items) {
          if ([candidate.text isEqualToString:text]) {
              candidate.pinned = !candidate.pinned;
              break;
          }
      }
      [self saveLocked];
      [self releaseFileLock:lock];
    });
}

- (void)deleteItem:(CMItem *)item {
    if (!item) {
        return;
    }
    NSString *text = item.text;
    dispatch_sync(_queue, ^{
      int lock = [self acquireFileLock];
      [self loadLocked];
      NSMutableIndexSet *toRemove = [NSMutableIndexSet indexSet];
      [self->_items enumerateObjectsUsingBlock:^(CMItem *candidate, NSUInteger index, BOOL *stop) {
        if ([candidate.text isEqualToString:text]) {
            [toRemove addIndex:index];
        }
      }];
      [self->_items removeObjectsAtIndexes:toRemove];
      [self saveLocked];
      [self releaseFileLock:lock];
    });
}

- (void)clearAll {
    dispatch_sync(_queue, ^{
      int lock = [self acquireFileLock];
      [self->_items removeAllObjects];
      [self writeHistoryArrayToPreferences:@[]];
      [[NSFileManager defaultManager] removeItemAtPath:[CMStore historyPath] error:NULL];
      [self releaseFileLock:lock];
    });
}

- (NSString *)exportToTextFile {
    __block NSString *result = nil;
    dispatch_sync(_queue, ^{
      [self loadLocked];
      NSMutableString *output = [NSMutableString string];
      NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
      formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
      for (CMItem *item in self->_items) {
          NSString *stamp = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:item.timestamp]];
          [output appendFormat:@"[%@] %@\n", stamp, item.text];
      }
      NSString *path = [CMStore exportPath];
      if ([output writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]) {
          chmod([path fileSystemRepresentation], 0644);
          result = path;
      }
    });
    return result;
}

@end
