#import <AppKit/AppKit.h>
@interface YMWindowPlacement : NSObject
// Main-thread-only. Checkpoints retain exact AX identities, never app-wide groups.
- (NSDictionary *)moveWindow:(NSDictionary *)window workspace:(NSString *)workspace display:(CGDirectDisplayID)display options:(NSDictionary *)options;
- (NSDictionary *)restoreWorkspace:(NSString *)workspace;
- (NSUInteger)countForWorkspace:(NSString *)workspace;
@end
