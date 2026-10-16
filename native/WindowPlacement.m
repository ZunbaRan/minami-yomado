#import "WindowPlacement.h"
#import "Common.h"
#import "VDVirtualDisplay.h"
#import "PlacementPolicy.h"
#include <dlfcn.h>
#include <libproc.h>

static NSString *YMProcessIdentity(pid_t pid) {
    struct proc_bsdinfo info = {0};
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info)) return nil;
    return [NSString stringWithFormat:@"%llu:%llu", info.pbi_start_tvsec, info.pbi_start_tvusec];
}

static id YMAttribute(AXUIElementRef element, CFStringRef key) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, key, &value) != kAXErrorSuccess) return nil;
    return CFBridgingRelease(value);
}
static CGRect YMAXRect(AXUIElementRef element) {
    id p = YMAttribute(element, kAXPositionAttribute), s = YMAttribute(element, kAXSizeAttribute);
    CGPoint point; CGSize size;
    if (!p || !s || CFGetTypeID((__bridge CFTypeRef)p) != AXValueGetTypeID() || CFGetTypeID((__bridge CFTypeRef)s) != AXValueGetTypeID()
        || !AXValueGetValue((__bridge AXValueRef)p, kAXValueCGPointType, &point)
        || !AXValueGetValue((__bridge AXValueRef)s, kAXValueCGSizeType, &size)) return CGRectNull;
    return (CGRect){point,size};
}
static BOOL YMNear(CGRect a, CGRect b) {
    return !CGRectIsNull(a) && fabs(a.origin.x-b.origin.x)<3 && fabs(a.origin.y-b.origin.y)<3 && fabs(a.size.width-b.size.width)<3 && fabs(a.size.height-b.size.height)<3;
}
static NSDictionary *YMCGWindow(CGWindowID ident) {
    NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));
    if (!windows) YMThrow(@"inventory_unavailable", @"Cannot read window inventory; restoration checkpoints retained.");
    for (NSDictionary *w in windows) if ([w[(id)kCGWindowNumber] unsignedIntValue] == ident) return w;
    return nil;
}
static CGRect YMCGRect(CGWindowID ident) {
    NSDictionary *w = YMCGWindow(ident); CGRect r;
    return w && CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)w[(id)kCGWindowBounds], &r) ? r : CGRectNull;
}
static id YMResolveWindow(pid_t pid, CGWindowID ident, CGRect bounds, NSString *title) {
    typedef AXError (*WindowIDFunction)(AXUIElementRef, CGWindowID *);
    WindowIDFunction windowID = (WindowIDFunction)dlsym(RTLD_DEFAULT, "_AXUIElementGetWindow");
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    NSArray *roots = YMAttribute(app, kAXWindowsAttribute); CFRelease(app);
    NSMutableArray *queue = [NSMutableArray arrayWithArray:[roots isKindOfClass:NSArray.class] ? roots : @[]];
    NSMutableArray *seen = [NSMutableArray array], *fallback = [NSMutableArray array];
    while (queue.count && seen.count < 256) {
        id object = queue.firstObject; [queue removeObjectAtIndex:0];
        BOOL visited = NO; for (id old in seen) if (CFEqual((__bridge CFTypeRef)old, (__bridge CFTypeRef)object)) { visited = YES; break; }
        if (visited) continue; [seen addObject:object];
        AXUIElementRef element = (__bridge AXUIElementRef)object;
        CGWindowID actual = 0;
        AXError identityResult = windowID ? windowID(element, &actual) : kAXErrorNotImplemented;
        if (identityResult == kAXErrorSuccess && actual == ident) return object;
        NSString *role = YMAttribute(element, kAXRoleAttribute);
        if (YMAllowsWindowIdentityFallback(identityResult, actual) && [role isEqual:(__bridge NSString *)kAXWindowRole] && YMNear(YMAXRect(element), bounds)
            && title.length && [YMAttribute(element, kAXTitleAttribute) isEqual:title]) [fallback addObject:object];
        NSArray *children = YMAttribute(element, kAXChildrenAttribute);
        if ([children isKindOfClass:NSArray.class] && queue.count + children.count < 1024) [queue addObjectsFromArray:children];
    }
    if (fallback.count == 1) return fallback.firstObject;
    YMThrow(@"window_not_resolved", @"Could not resolve this exact window safely through Accessibility. No app-wide move was attempted."); return nil;
}
static void YMSetFrame(AXUIElementRef element, CGWindowID ident, CGRect frame) {
    CGSize size = frame.size; CGPoint origin = frame.origin;
    CGRect old = YMAXRect(element);
    if (CGRectIsNull(old)) YMThrow(@"window_unavailable", @"Window's Accessibility geometry is unavailable.");
    if (fabs(old.size.width-size.width)>2 || fabs(old.size.height-size.height)>2) {
        AXValueRef value = AXValueCreate(kAXValueCGSizeType, &size);
        AXError result = AXUIElementSetAttributeValue(element, kAXSizeAttribute, value); CFRelease(value);
        if (result != kAXErrorSuccess) YMThrow(@"resize_failed", @"Application refused resizing; checkpoint retained.");
    }
    AXValueRef position = AXValueCreate(kAXValueCGPointType, &origin);
    AXError result = AXUIElementSetAttributeValue(element, kAXPositionAttribute, position); CFRelease(position);
    if (result != kAXErrorSuccess) YMThrow(@"move_failed", @"Application refused positioning; checkpoint retained.");
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.5];
    while (!YMNear(YMCGRect(ident), frame) && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    if (!YMNear(YMCGRect(ident), frame)) YMThrow(@"placement_unverified", @"Window did not reach the requested bounds; checkpoint retained. Call workspace_restore.");
}

@interface YMWindowPlacement ()
@property(nonatomic) NSMutableDictionary<NSNumber *, NSMutableDictionary *> *checkpoints;
@end
@implementation YMWindowPlacement
- (instancetype)init { if ((self = [super init])) _checkpoints = [NSMutableDictionary dictionary]; return self; }
- (NSUInteger)countForWorkspace:(NSString *)workspace {
    NSUInteger n = 0; for (NSDictionary *p in self.checkpoints.allValues) if ([p[@"workspace_id"] isEqual:workspace]) n++; return n;
}
- (NSDictionary *)moveWindow:(NSDictionary *)window workspace:(NSString *)workspace display:(CGDirectDisplayID)display options:(NSDictionary *)options {
    if (!AXIsProcessTrusted()) YMThrow(@"accessibility_required", @"Enable Accessibility for the responsible host/helper before moving windows.");
    pid_t pid = [window[@"pid"] intValue]; CGWindowID ident = [window[@"window_id"] unsignedIntValue];
    if (pid == getpid()) YMThrow(@"invalid_target", @"The workspace viewer cannot be moved into its own workspace.");
    NSDictionary *fresh = YMCGWindow(ident);
    if (!fresh || [fresh[(id)kCGWindowOwnerPID] intValue] != pid) YMThrow(@"window_changed", @"Window owner changed; refresh window_list.");
    NSString *identity = YMProcessIdentity(pid);
    if (!identity) YMThrow(@"window_unavailable", @"Cannot establish window-owner identity.");
    CGRect original = YMCGRect(ident), target = CGDisplayBounds(display);
    if (CGRectIsNull(original)) YMThrow(@"window_unavailable", @"Window is no longer available.");
    CGSize size = CGSizeMake(MIN(original.size.width, target.size.width-48), MIN(original.size.height, target.size.height-80));
    CGFloat x = options[@"x"] ? [options[@"x"] doubleValue] : (target.size.width-size.width)/2;
    CGFloat y = options[@"y"] ? [options[@"y"] doubleValue] : 48;
    CGRect destination = CGRectMake(target.origin.x+x, target.origin.y+y, size.width, size.height);
    if (!isfinite(x) || !isfinite(y) || !CGRectContainsRect(target, destination)) YMThrow(@"invalid_argument", @"Window placement must fit within the workspace.");
    NSNumber *key = @(ident); NSMutableDictionary *checkpoint = self.checkpoints[key];
    if (checkpoint && (![checkpoint[@"pid"] isEqual:@(pid)] || ![checkpoint[@"launch"] isEqual:identity])) {
        [self.checkpoints removeObjectForKey:key]; checkpoint = nil;
    }
    if (!checkpoint) {
        CGDirectDisplayID source = 0; CGDirectDisplayID outputs[64]; uint32_t count;
        CGGetActiveDisplayList(64, outputs, &count);
        CGPoint center = CGPointMake(CGRectGetMidX(original), CGRectGetMidY(original));
        for (uint32_t i = 0; i < count; i++) if (CGRectContainsPoint(CGDisplayBounds(outputs[i]), center)) { source = outputs[i]; break; }
        if (!source || [VDVirtualDisplay isVirtualDisplay:source]) YMThrow(@"physical_origin_required", @"First placement must start on a physical display so restoration has a verified destination.");
        if (!YMRestorableOrigin(original, CGDisplayBounds(source))) YMThrow(@"unrestorable_origin", @"Place the complete window within one physical display before moving it into a workspace.");
        id element = YMResolveWindow(pid, ident, original, window[@"title"]);
        checkpoint = [@{@"workspace_id":workspace, @"window_id":key, @"pid":@(pid), @"launch":identity,
            @"element":element, @"original":YMRect(original), @"source_display":@(source)} mutableCopy];
        self.checkpoints[key] = checkpoint;
    }
    checkpoint[@"workspace_id"] = workspace;
    YMSetFrame((__bridge AXUIElementRef)checkpoint[@"element"], ident, destination);
    return @{@"window_id":key, @"pid":@(pid), @"workspace_id":workspace, @"bounds":YMRect(YMCGRect(ident)), @"original_bounds":checkpoint[@"original"]};
}
- (NSDictionary *)restoreWorkspace:(NSString *)workspace {
    NSMutableArray *restored = [NSMutableArray array], *closed = [NSMutableArray array];
    for (NSNumber *key in self.checkpoints.allKeys.copy) {
        NSDictionary *p = self.checkpoints[key]; if (![p[@"workspace_id"] isEqual:workspace]) continue;
        pid_t pid = [p[@"pid"] intValue]; NSDictionary *window = YMCGWindow(key.unsignedIntValue);
        NSString *identity = YMProcessIdentity(pid);
        if (!window || [window[(id)kCGWindowOwnerPID] intValue] != pid || ![identity isEqual:p[@"launch"]]) {
            [self.checkpoints removeObjectForKey:key]; [closed addObject:key]; continue;
        }
        CGDirectDisplayID source = [p[@"source_display"] unsignedIntValue]; CGRect original = YMParseRect(p[@"original"]);
        if (!CGDisplayIsActive(source) || [VDVirtualDisplay isVirtualDisplay:source] || !YMRestorableOrigin(original, CGDisplayBounds(source)))
            YMThrow(@"restore_destination_changed", @"Original physical display placement is no longer available. Keep the workspace running.");
        YMSetFrame((__bridge AXUIElementRef)p[@"element"], key.unsignedIntValue, original);
        [self.checkpoints removeObjectForKey:key]; [restored addObject:@{@"window_id":key, @"bounds":YMRect(original)}];
    }
    return @{@"restored":restored, @"already_closed":closed};
}
@end
