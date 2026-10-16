#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

static inline void YMThrow(NSString *code, NSString *message) {
    @throw [NSException exceptionWithName:@"WorkspaceError" reason:message userInfo:@{@"code":code}];
}
// Never block the AppKit run loop waiting for ScreenCaptureKit or topology work.
static inline id YMMain(id (^block)(void)) {
    if (NSThread.isMainThread) return block();
    __block id result; __block NSException *failure;
    dispatch_sync(dispatch_get_main_queue(), ^{ @try { result = block(); } @catch (NSException *e) { failure = e; } });
    if (failure) @throw failure;
    return result;
}
static inline NSDictionary *YMRect(CGRect r) {
    return @{@"x":@(r.origin.x), @"y":@(r.origin.y), @"width":@(r.size.width), @"height":@(r.size.height)};
}
static inline CGRect YMParseRect(NSDictionary *r) {
    return CGRectMake([r[@"x"] doubleValue], [r[@"y"] doubleValue], [r[@"width"] doubleValue], [r[@"height"] doubleValue]);
}
static inline void YMCheck(BOOL ok, NSError *e) {
    if (!ok) YMThrow(@"native_error", e.localizedDescription ?: @"Native operation failed.");
}
