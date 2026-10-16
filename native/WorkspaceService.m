#import "WorkspaceService.h"
#import "Common.h"
#import "VDVirtualDisplay.h"
#import "YMDisplayTopology.h"
#import "DesktopPreview.h"
#import "WindowPlacement.h"
#import "../app/AppWorkspacePolicy.h"

@interface YMWorkspaceService ()
@property(nonatomic) NSMutableDictionary<NSString *, NSMutableDictionary *> *profiles;
@property(nonatomic) NSMutableDictionary<NSString *, VDVirtualDisplay *> *displays;
@property(nonatomic) YMDisplayTopology *topology;
@property(nonatomic) YMDisplayTopologySnapshot *pendingRecovery;
@property(nonatomic) CGDirectDisplayID pendingRemovedID;
@property(nonatomic) NSString *file;
@property(nonatomic) NSMutableDictionary<NSString *, YMDesktopPreview *> *previews;
@property(nonatomic) YMWindowPlacement *placement;
@property(nonatomic) BOOL shuttingDown;
@end

@implementation YMWorkspaceService
- (instancetype)initWithDirectory:(NSString *)directory {
    if ((self = [super init])) {
        _file = [directory stringByAppendingPathComponent:@"profiles.json"];
        _profiles = [NSMutableDictionary dictionary]; _displays = [NSMutableDictionary dictionary];
        _topology = [YMDisplayTopology new];
        _previews = [NSMutableDictionary dictionary]; _placement = [YMWindowPlacement new];
        NSData *data = [NSData dataWithContentsOfFile:_file];
        if (data) {
            id saved = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
            if (![saved isKindOfClass:NSArray.class]) YMThrow(@"invalid_state", @"Invalid profiles file; restore it before starting the helper.");
            for (id p in saved) {
                if (![p isKindOfClass:NSDictionary.class] || ![p[@"id"] isKindOfClass:NSString.class] || ![p[@"serial"] isKindOfClass:NSNumber.class])
                    YMThrow(@"invalid_state", @"Invalid saved workspace.");
                [self validateSettings:p]; _profiles[p[@"id"]] = [p mutableCopy];
            }
        }
    }
    return self;
}
- (void)validateSettings:(NSDictionary *)p {
    if (![p[@"name"] isKindOfClass:NSString.class] || ![p[@"name"] length] || [p[@"name"] length] > 100)
        YMThrow(@"invalid_argument", @"name must be 1–100 characters.");
    for (NSString *key in @[@"width", @"height", @"hidpi"]) if (![p[key] isKindOfClass:NSNumber.class])
        YMThrow(@"invalid_argument", [key stringByAppendingString:@" must be numeric/boolean."]);
    double w = [p[@"width"] doubleValue], h = [p[@"height"] doubleValue];
    NSUInteger scale = [p[@"hidpi"] boolValue] ? 2 : 1;
    if (w != floor(w) || h != floor(h) || w < 320 || h < 240 || w*scale > 8192 || h*scale > 8192 || w*h*scale*scale > 33554432)
        YMThrow(@"invalid_argument", @"Invalid display dimensions (minimum 320×240; maximum 8192 per pixel dimension and 32 million pixels).");
}
- (void)save {
    NSError *e; NSData *data = [NSJSONSerialization dataWithJSONObject:self.profiles.allValues options:NSJSONWritingPrettyPrinted error:&e];
    YMCheck(data && [data writeToFile:self.file options:NSDataWritingAtomic error:&e], e);
}
- (NSMutableDictionary *)profile:(id)key {
    if (![key isKindOfClass:NSString.class] || !self.profiles[key]) YMThrow(@"not_found", @"Unknown workspace_id.");
    return self.profiles[key];
}
- (NSDictionary *)state:(NSString *)key {
    NSMutableDictionary *state = [self.profiles[key] mutableCopy];
    [state removeObjectForKey:@"serial"];
    VDVirtualDisplay *display = self.displays[key];
    CGDirectDisplayID ident = display.displayID;
    BOOL active = ident && CGDisplayIsActive(ident);
    state[@"running"] = @(active); state[@"display_id"] = ident ? @(ident) : NSNull.null;
    state[@"bounds"] = active ? YMRect(CGDisplayBounds(ident)) : NSNull.null;
    state[@"recovery_required"] = @(self.pendingRecovery != nil);
    state[@"pixel_width"] = @([state[@"width"] integerValue] * ([state[@"hidpi"] boolValue] ? 2 : 1));
    state[@"pixel_height"] = @([state[@"height"] integerValue] * ([state[@"hidpi"] boolValue] ? 2 : 1));
    state[@"tracked_windows"] = YMMain(^id{ return @([self.placement countForWorkspace:key]); });
    state[@"preview"] = self.previews[key] ? [self.previews[key] status] : (id)NSNull.null;
    return state;
}
- (void)checkPhysicalMain {
    CGDirectDisplayID main = CGMainDisplayID();
    if (!main || !CGDisplayIsActive(main) || [VDVirtualDisplay isVirtualDisplay:main])
        YMThrow(@"physical_main_required", @"Keep an active physical display as main before managing virtual workspaces.");
}
- (void)checkRecovery {
    if (self.pendingRecovery) YMThrow(@"recovery_required", @"Topology recovery is pending; call workspace_recover before changing displays.");
}
- (void)recover:(YMDisplayTopologySnapshot *)snapshot removed:(CGDirectDisplayID)ident {
    NSError *e;
    if (![self.topology restoreAndVerifySnapshot:snapshot excludingDisplayID:ident error:&e]) {
        self.pendingRecovery = snapshot; self.pendingRemovedID = ident;
        YMThrow(@"recovery_required", e.localizedDescription ?: @"Display recovery needs attention.");
    }
    self.pendingRecovery = nil; self.pendingRemovedID = 0;
}
- (NSDictionary *)start:(NSString *)key {
    [self checkRecovery]; [self checkPhysicalMain];
    NSMutableDictionary *p = [self profile:key];
    if (self.displays[key]) {
        if (![self.topology isExtendedTarget:self.displays[key].displayID width:[p[@"width"] unsignedIntegerValue] height:[p[@"height"] unsignedIntegerValue] hiDPI:[p[@"hidpi"] boolValue]])
            YMThrow(@"display_changed", @"The owned display is no longer in the expected extended configuration.");
        return [self state:key];
    }
    NSError *e;
    YMDisplayTopologySnapshot *baseline = [self.topology captureSnapshotWithError:&e]; YMCheck(baseline != nil, e);
    VDVirtualDisplay *d = [[VDVirtualDisplay alloc] initWithSerialNumber:[p[@"serial"] unsignedIntValue]];
    __block NSError *creationError;
    BOOL created = [YMMain(^id{ return @([d createWithWidth:[p[@"width"] unsignedIntegerValue] height:[p[@"height"] unsignedIntegerValue]
        hiDPI:[p[@"hidpi"] boolValue] name:p[@"name"] error:&creationError]); }) boolValue];
    CGDirectDisplayID ident = d.displayID;
    if (!created || ![self.topology configureAndVerifyNewDisplay:ident width:[p[@"width"] unsignedIntegerValue]
        height:[p[@"height"] unsignedIntegerValue] hiDPI:[p[@"hidpi"] boolValue] baseline:baseline error:&e]) {
        YMMain(^id{ [d destroy]; return nil; });
        [self recover:baseline removed:ident]; YMCheck(NO, creationError ?: e);
    }
    self.displays[key] = d;
    return [self state:key];
}
- (NSArray *)windows {
    NSMutableArray *result = [NSMutableArray array];
    NSArray *items = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
    if (!items) YMThrow(@"inventory_unavailable", @"Window inventory is unavailable; no display will be removed.");
    for (NSDictionary *w in items) {
        if ([w[(id)kCGWindowLayer] integerValue] != 0) continue;
        CGRect bounds; if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)w[(id)kCGWindowBounds], &bounds)) continue;
        // Reuse upstream's ordinary-window geometry policy. Include minimized
        // windows too, but omit macOS's per-app 30pt menu-bar backing surfaces.
        if (!YMWorkspaceVisibleOrdinaryGeometry(YMRect(bounds), [w[(id)kCGWindowLayer] integerValue], YES, [w[(id)kCGWindowAlpha] doubleValue])) continue;
        [result addObject:@{@"window_id":w[(id)kCGWindowNumber], @"pid":w[(id)kCGWindowOwnerPID],
            @"title":w[(id)kCGWindowName] ?: @"", @"app":w[(id)kCGWindowOwnerName] ?: @"", @"bounds":YMRect(bounds)}];
    }
    return result;
}
- (NSDictionary *)stop:(NSString *)key {
    [self profile:key]; [self checkRecovery];
    VDVirtualDisplay *d = self.displays[key]; if (!d) return [self state:key];
    [self checkPhysicalMain];
    if ([YMMain(^id{ return @([self.placement countForWorkspace:key]); }) unsignedIntegerValue])
        YMThrow(@"restore_required", @"Call workspace_restore to resolve this workspace's window checkpoints before stopping.");
    CGRect target = CGDisplayBounds(d.displayID);
    for (NSDictionary *window in [self windows]) if (CGRectIntersectsRect(target, YMParseRect(window[@"bounds"])))
        YMThrow(@"workspace_occupied", @"Workspace still contains windows; restore/move them before stopping.");
    NSError *e; YMDisplayTopologySnapshot *before = [self.topology captureSnapshotWithError:&e]; YMCheck(before != nil, e);
    CGDirectDisplayID ident = d.displayID;
    YMDisplayTopologySnapshot *survivors = [before snapshotByExcludingDisplayID:ident];
    if (!survivors) YMThrow(@"display_changed", @"Cannot establish surviving display layout.");
    [self.previews[key] close]; [self.previews removeObjectForKey:key];
    YMMain(^id{ [d destroy]; return nil; }); [self.displays removeObjectForKey:key];
    [self recover:survivors removed:ident]; return [self state:key];
}
- (NSDictionary *)handle:(NSString *)method arguments:(NSDictionary *)a {
    if (self.shuttingDown) YMThrow(@"shutting_down", @"Helper is shutting down; reconnect after it exits.");
    if ([method isEqual:@"service_status"]) return @{@"version":@"0.1.0", @"pid":@(getpid()), @"virtual_display_api":@(VDVirtualDisplay.isAPIAvailable),
        @"accessibility":@(AXIsProcessTrusted()), @"screen_recording":@(CGPreflightScreenCaptureAccess()), @"recovery_required":@(self.pendingRecovery != nil)};
    if ([method isEqual:@"workspace_list"]) {
        NSMutableArray *items = [NSMutableArray array]; for (NSString *key in [self.profiles.allKeys sortedArrayUsingSelector:@selector(compare:)]) [items addObject:[self state:key]];
        NSMutableArray *outputs = [NSMutableArray array];
        for (NSDictionary *raw in [VDVirtualDisplay onlineDisplays]) {
            NSMutableDictionary *output = [NSMutableDictionary dictionary];
            for (NSString *field in @[@"displayID", @"name", @"bounds", @"isVirtual", @"main", @"active", @"mirrorOf", @"pixelWidth", @"pixelHeight", @"refreshRate"])
                if (raw[field]) output[field] = raw[field];
            [outputs addObject:output];
        }
        return @{@"workspaces":items, @"displays":outputs};
    }
    if ([method isEqual:@"window_list"]) return @{@"windows":[self windows]};
    if ([method isEqual:@"workspace_recover"]) {
        if (self.pendingRecovery) [self recover:self.pendingRecovery removed:self.pendingRemovedID];
        return @{@"recovered":@YES};
    }
    if ([method isEqual:@"service_shutdown"]) {
        if (self.displays.count || self.pendingRecovery) YMThrow(@"workspace_active", @"Stop all owned displays and resolve recovery before shutdown.");
        self.shuttingDown = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
        return @{@"shutting_down":@YES};
    }
    if ([method isEqual:@"workspace_create"]) {
        [self checkRecovery];
        NSString *key = NSUUID.UUID.UUIDString;
        NSMutableDictionary *p = [@{@"id":key, @"name":a[@"name"] ?: @"Agent Workspace", @"width":a[@"width"] ?: @1920,
            @"height":a[@"height"] ?: @1080, @"hidpi":a[@"hidpi"] ?: @NO, @"serial":@(arc4random_uniform(0x0fffffff)+0x60000000)} mutableCopy];
        [self validateSettings:p]; self.profiles[key] = p;
        @try { [self save]; } @catch (NSException *e) { [self.profiles removeObjectForKey:key]; @throw e; }
        // Creation saves a stopped profile. Starting is explicit and recoverable.
        return [self state:key];
    }
    NSString *key = a[@"workspace_id"]; NSMutableDictionary *p = [self profile:key];
    if ([method isEqual:@"workspace_get"]) return [self state:key];
    if ([method isEqual:@"workspace_restore"]) return YMMain(^id{ return [self.placement restoreWorkspace:key]; });
    if ([method isEqual:@"preview_close"]) {
        [self.previews[key] close]; [self.previews removeObjectForKey:key]; return @{@"closed":@YES};
    }
    if ([method isEqual:@"preview_configure"]) {
        if (!self.previews[key] || [[[self.previews[key] status] objectForKey:@"state"] isEqual:@"closed"])
            YMThrow(@"preview_not_open", @"Open a preview before configuring its bounds.");
        [self.previews[key] configure:a]; return [self.previews[key] status];
    }
    if ([method isEqual:@"workspace_move_window"] || [method isEqual:@"preview_open"]) {
        [self checkRecovery]; [self checkPhysicalMain];
        VDVirtualDisplay *d = self.displays[key];
        if (!d || ![self.topology isExtendedTarget:d.displayID width:[p[@"width"] unsignedIntegerValue] height:[p[@"height"] unsignedIntegerValue] hiDPI:[p[@"hidpi"] boolValue]])
            YMThrow(@"workspace_not_ready", @"Start the workspace and verify its display layout before using it.");
        if ([method isEqual:@"workspace_move_window"]) {
            if (![a[@"window_id"] isKindOfClass:NSNumber.class] || ![a[@"pid"] isKindOfClass:NSNumber.class]) YMThrow(@"invalid_argument", @"window_id and pid are required.");
            NSDictionary *target;
            for (NSDictionary *window in [self windows]) if ([window[@"window_id"] isEqual:a[@"window_id"]] && [window[@"pid"] isEqual:a[@"pid"]]) { target = window; break; }
            if (!target) YMThrow(@"window_not_found", @"Refresh window_list; the requested window/PID pair was not found.");
            return YMMain(^id{ return [self.placement moveWindow:target workspace:key display:d.displayID options:a]; });
        }
        if (self.previews[key]) {
            NSString *phase = [self.previews[key] status][@"state"];
            if ([phase isEqual:@"closed"] || [phase isEqual:@"error"]) { [self.previews[key] close]; [self.previews removeObjectForKey:key]; }
            else return [self.previews[key] status];
        }
        self.previews[key] = [[YMDesktopPreview alloc] initWithDisplayID:d.displayID name:p[@"name"] options:a];
        return [self.previews[key] status];
    }
    if ([method isEqual:@"workspace_start"]) return [self start:key];
    if ([method isEqual:@"workspace_stop"]) return [self stop:key];
    if ([method isEqual:@"workspace_configure"]) {
        if (self.displays[key] && (a[@"width"] || a[@"height"] || a[@"hidpi"]))
            YMThrow(@"workspace_running", @"Stop the workspace before changing resolution or HiDPI.");
        NSMutableDictionary *updated = p.mutableCopy;
        for (NSString *field in @[@"name", @"width", @"height", @"hidpi"]) if (a[field]) updated[field] = a[field];
        [self validateSettings:updated]; self.profiles[key] = updated;
        @try { [self save]; } @catch (NSException *e) { self.profiles[key] = p; @throw e; }
        NSMutableDictionary *result = [[self state:key] mutableCopy];
        result[@"display_name_updates_on_restart"] = @(self.displays[key] != nil && a[@"name"] != nil); return result;
    }
    if ([method isEqual:@"workspace_destroy"]) {
        if (self.displays[key]) YMThrow(@"workspace_running", @"Stop the workspace before deleting its profile.");
        [self checkRecovery]; [self.profiles removeObjectForKey:key];
        @try { [self save]; } @catch (NSException *e) { self.profiles[key] = p; @throw e; }
        return @{@"deleted":@YES, @"workspace_id":key};
    }
    YMThrow(@"unknown_method", @"Unknown workspace operation."); return @{};
}
@end
