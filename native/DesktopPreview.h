#import <AppKit/AppKit.h>
@interface YMDesktopPreview : NSObject
// Called from the serial operation queue; never from the AppKit main thread.
- (instancetype)initWithDisplayID:(CGDirectDisplayID)displayID name:(NSString *)name options:(NSDictionary *)options framePath:(NSString *)framePath;
- (NSDictionary *)status;
- (void)configure:(NSDictionary *)options;
- (void)close;
@end
