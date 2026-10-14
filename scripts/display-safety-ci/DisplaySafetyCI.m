#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import "VDVirtualDisplay.h"
#import "YMDisplayTopology.h"
#import "AppWorkspaceView.h"

// Resolve the real controller classes linked from unchanged production source.
// The production application main is renamed at compile time and never called.
@interface NSObject (YMCIAccess)
- (BOOL)canMoveIntoProfile:(id)profile;
- (void)choose:(id)sender;
- (NSMenu *)restoreMenu;
@end

// Only this fixture pasteboard is read; the user's general clipboard is unused.
@interface YMCIIncomingDrag : NSObject
@property NSPasteboard *draggingPasteboard;
@end
@implementation YMCIIncomingDrag
@end

static NSString *Evidence;
static NSMutableArray *Checks;
static NSMutableArray<VDVirtualDisplay *> *Owned;
static NSUInteger Blocked;
static unsigned Sequence;
static NSWindow *FixtureWindow;
static NSRect InitialWindowFrame;

static void Save(NSString *name, id value) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
    if (!data || ![data writeToFile:[Evidence stringByAppendingPathComponent:name] options:NSDataWritingAtomic error:&error]) {
        fprintf(stderr, "Evidence serialization failed.\n"); exit(2);
    }
}
static void Check(NSString *name, BOOL passed, NSString *detail) {
    [Checks addObject:@{@"name":name, @"passed":@(passed), @"detail":detail ?: @""}];
    printf("%s %s\n", passed ? "PASS" : "FAIL", name.UTF8String);
    Save(@"checks.json", Checks);
}
static void Block(NSString *name, NSString *reason) {
    Blocked++;
    [Checks addObject:@{@"name":name, @"blocked":@YES, @"detail":reason ?: @"Unsupported fixture setup"}];
    printf("BLOCKED %s\n", name.UTF8String);
    Save(@"checks.json", Checks);
}
static void Pump(double seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (until.timeIntervalSinceNow > 0)
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:MIN(0.05, until.timeIntervalSinceNow)]];
}
static NSArray *Inventory(void) {
    CGDirectDisplayID ids[64] = {0}; uint32_t count = 0;
    if (CGGetOnlineDisplayList(64, ids, &count) != kCGErrorSuccess) return @[];
    NSMutableArray *rows = [NSMutableArray array];
    for (uint32_t i = 0; i < count; i++) {
        CGDirectDisplayID d = ids[i]; CGRect b = CGDisplayBounds(d);
        NSMutableDictionary *r = [@{@"id":@(d), @"main":@(CGDisplayIsMain(d)),
            @"active":@(CGDisplayIsActive(d)), @"online":@(CGDisplayIsOnline(d)),
            @"mirrorOf":@(CGDisplayMirrorsDisplay(d)), @"inMirrorSet":@(CGDisplayIsInMirrorSet(d)),
            @"rotation":@(CGDisplayRotation(d)),
            @"bounds":@{@"x":@(b.origin.x), @"y":@(b.origin.y), @"width":@(b.size.width), @"height":@(b.size.height)}} mutableCopy];
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(d);
        if (mode) {
            r[@"mode"] = @{@"width":@(CGDisplayModeGetWidth(mode)), @"height":@(CGDisplayModeGetHeight(mode)),
                @"pixelWidth":@(CGDisplayModeGetPixelWidth(mode)), @"pixelHeight":@(CGDisplayModeGetPixelHeight(mode)),
                @"refresh":@(CGDisplayModeGetRefreshRate(mode)), @"flags":@(CGDisplayModeGetIOFlags(mode)),
                @"id":@(CGDisplayModeGetIODisplayModeID(mode))};
            CGDisplayModeRelease(mode);
        }
        [rows addObject:r];
    }
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b){return [a[@"id"] compare:b[@"id"]];}];
    return rows;
}
static NSDictionary *Row(NSArray *rows, CGDirectDisplayID d) {
    for (NSDictionary *r in rows) if ([r[@"id"] unsignedIntValue] == d) return r;
    return nil;
}
static BOOL Preserved(NSArray *before, NSArray *after) {
    for (NSDictionary *r in before) {
        NSDictionary *now = Row(after, [r[@"id"] unsignedIntValue]);
        if (![r isEqual:now]) return NO;
    }
    return YES;
}
static void Observe(NSString *label) {
    Save([NSString stringWithFormat:@"%02u-%@.json", ++Sequence, label],
        @{@"displays":Inventory(), @"fixtureWindowFrame":NSStringFromRect(FixtureWindow.frame),
          @"fixtureWindowUnchanged":@(NSEqualRects(InitialWindowFrame, FixtureWindow.frame))});
}
static VDVirtualDisplay *Make(NSUInteger w, NSUInteger h, BOOL hidpi) {
    VDVirtualDisplay *d = [[VDVirtualDisplay alloc] initWithSerialNumber:0x59430000 + (uint32_t)Owned.count + Sequence * 19];
    [Owned addObject:d]; NSError *error = nil;
    if (![d createWithWidth:w height:h hiDPI:hidpi name:@"yomado disposable CI fixture" error:&error]) {
        Check(@"private-api-create", NO, error.localizedDescription); return nil;
    }
    Pump(0.5); return d;
}
static BOOL Mirror(CGDirectDisplayID follower, CGDirectDisplayID root) {
    CGDisplayConfigRef config = NULL;
    if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess || !config) return NO;
    CGError e = CGConfigureDisplayMirrorOfDisplay(config, follower, root);
    if (e) { CGCancelDisplayConfiguration(config); return NO; }
    if (CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly) != kCGErrorSuccess) return NO;
    Pump(1.0);
    return CGDisplayMirrorsDisplay(follower) == root && CGDisplayIsInMirrorSet(follower);
}
static BOOL Move(CGDirectDisplayID d, int32_t x, int32_t y) {
    CGDisplayConfigRef config = NULL;
    if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess || !config) return NO;
    CGError e = CGConfigureDisplayOrigin(config, d, x, y);
    if (e) { CGCancelDisplayConfiguration(config); return NO; }
    e = CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly); Pump(0.4);
    return e == kCGErrorSuccess;
}
static id Profile(VDVirtualDisplay *display) {
    id p = [[NSClassFromString(@"YMManagedDisplay") alloc] init];
    [p setValue:display forKey:@"display"];
    [p setValue:@(display.logicalWidth) forKey:@"width"];
    [p setValue:@(display.logicalHeight) forKey:@"height"];
    [p setValue:@(display.hiDPI) forKey:@"hiDPI"];
    [p setValue:@NO forKey:@"topologyVerified"];
    return p;
}
static BOOL Configure(YMDisplayTopology *topology, VDVirtualDisplay *d, YMDisplayTopologySnapshot *baseline, NSString *label) {
    NSError *error = nil;
    BOOL ok = [topology configureAndVerifyNewDisplay:d.displayID width:d.logicalWidth height:d.logicalHeight hiDPI:d.hiDPI baseline:baseline error:&error];
    Check(label, ok, error.localizedDescription); Observe(label); return ok;
}
static void RemoveAndRestore(YMDisplayTopology *topology, VDVirtualDisplay *d, YMDisplayTopologySnapshot *baseline, NSArray *before, NSString *label) {
    CGDirectDisplayID removed = d.displayID; [d destroy]; NSError *error = nil;
    BOOL ok = [topology restoreAndVerifySnapshot:baseline excludingDisplayID:removed error:&error];
    Check(label, ok, error.localizedDescription);
    Check([label stringByAppendingString:@"-independent-inventory"], Preserved(before, Inventory()), @"All earlier mode, origin, mirror, rotation, main and active fields must be identical.");
    Check([label stringByAppendingString:@"-removed-offline"], !CGDisplayIsOnline(removed), nil);
    Observe(label);
}
static void CheckWorkspaceAdmissionUI(void) {
    YMAppWorkspaceView *view = [[YMAppWorkspaceView alloc] initWithFrame:NSMakeRect(0,0,360,203)];
    view.displayID = 901; view.displayName = @"CI recovery target";
    __block NSUInteger chosen = 0, restored = 0, dropped = 0;
    __block NSString *restoredIdentifier = nil;
    view.onChooseApplication = ^{ chosen++; };
    view.onRestoreBundleIdentifier = ^(NSString *bundleIdentifier) { restored++; restoredIdentifier = bundleIdentifier; };
    view.onDropApplication = ^(NSDictionary *payload) { (void)payload; dropped++; };
    NSArray *rows = @[@{@"bundleIdentifier":@"dev.chekusu.ci.fixture", @"appName":@"Disposable fixture", @"pid":@0,
        @"windowCount":@1, @"managedWindowCount":@1,
        @"appIcon":[NSImage imageWithSystemSymbolName:@"app.dashed" accessibilityDescription:nil]}];
    [view updateRows:rows virtualDisplayAvailable:YES accessibilityTrusted:YES];
    id icon = [[view valueForKeyPath:@"grid.icons"] firstObject];
    Check(@"workspace-default-admits-applications", view.acceptsApplications, nil);
    Check(@"workspace-default-add-enabled", [[view valueForKey:@"chooseButton"] isEnabled], nil);
    Check(@"workspace-existing-icon-movable", [[icon valueForKey:@"movable"] boolValue], nil);

    YMCIIncomingDrag *drag = [YMCIIncomingDrag new]; drag.draggingPasteboard = [NSPasteboard pasteboardWithUniqueName];
    NSData *payload = [NSJSONSerialization dataWithJSONObject:@{@"bundleIdentifier":@"dev.chekusu.ci.incoming", @"sourceDisplayID":@902} options:0 error:NULL];
    [drag.draggingPasteboard setData:payload forType:@"dev.chekusu.yomado.workspace-application"];
    id<NSDraggingInfo> incoming = (id<NSDraggingInfo>)drag;
    Check(@"workspace-valid-incoming-control", [view draggingEntered:incoming] == NSDragOperationMove, nil);
    Check(@"workspace-valid-drop-control", [view performDragOperation:incoming] && dropped == 1, nil);
    (void)[view draggingEntered:incoming];
    Check(@"workspace-highlight-positive-control", [[view valueForKey:@"highlighted"] boolValue], nil);
    view.acceptsApplications = NO;
    Check(@"workspace-recovery-clears-drop-highlight", ![[view valueForKey:@"highlighted"] boolValue], nil);
    Check(@"workspace-recovery-disables-add-button", ![[view valueForKey:@"chooseButton"] isEnabled], nil);
    NSEvent *menuEvent = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:0];
    NSMenu *menu = [view menuForEvent:menuEvent];
    Check(@"workspace-recovery-disables-add-menu", menu.numberOfItems > 0 && !menu.itemArray.firstObject.enabled, nil);
    [view choose:nil];
    Check(@"workspace-recovery-direct-add-action-denied", chosen == 0, nil);
    Check(@"workspace-recovery-rejects-incoming-drag", [view draggingEntered:incoming] == NSDragOperationNone, nil);
    Check(@"workspace-recovery-rejects-prepare", ![view prepareForDragOperation:incoming], nil);
    Check(@"workspace-recovery-rejects-drop", ![view performDragOperation:incoming] && dropped == 1, nil);
    id retainedIcon = [[view valueForKeyPath:@"grid.icons"] firstObject];
    Check(@"workspace-recovery-retains-existing-icon", retainedIcon == icon, nil);
    Check(@"workspace-recovery-keeps-outgoing-icon-movable", [[retainedIcon valueForKey:@"movable"] boolValue], nil);
    NSMenu *returnMenu = [retainedIcon restoreMenu];
    NSMenuItem *returnItem = returnMenu.itemArray.firstObject;
    Check(@"workspace-recovery-return-menu-enabled", returnItem != nil && returnItem.enabled, nil);
    if (returnItem.enabled) [NSApp sendAction:returnItem.action to:returnItem.target from:returnItem];
    Check(@"workspace-recovery-return-callback-works", restored == 1 && [restoredIdentifier isEqual:@"dev.chekusu.ci.fixture"], nil);

    // Permission revocation still closes outgoing actions; recovery admission
    // must not accidentally bypass Accessibility authorization.
    [view updateRows:rows virtualDisplayAvailable:YES accessibilityTrusted:NO];
    icon = [[view valueForKeyPath:@"grid.icons"] firstObject];
    Check(@"workspace-untrusted-disables-outgoing", ![[icon valueForKey:@"movable"] boolValue], nil);
    Check(@"workspace-untrusted-disables-return", ![icon restoreMenu].itemArray.firstObject.enabled, nil);
    [view updateRows:rows virtualDisplayAvailable:YES accessibilityTrusted:YES];
    icon = [[view valueForKeyPath:@"grid.icons"] firstObject];
    Check(@"workspace-trust-restored-keeps-recovery-outgoing", [[icon valueForKey:@"movable"] boolValue] && [icon restoreMenu].itemArray.firstObject.enabled, nil);
    Check(@"workspace-trust-restored-still-denies-incoming", ![[view valueForKey:@"chooseButton"] isEnabled] && [view draggingEntered:incoming] == NSDragOperationNone, nil);
    view.acceptsApplications = YES;
    [view choose:nil];
    Check(@"workspace-verification-restores-add", [[view valueForKey:@"chooseButton"] isEnabled] && chosen == 1, nil);
    Check(@"workspace-verification-restores-incoming", [view performDragOperation:incoming] && dropped == 2, nil);
    [view updateRows:rows virtualDisplayAvailable:NO accessibilityTrusted:YES];
    icon = [[view valueForKeyPath:@"grid.icons"] firstObject];
    Check(@"workspace-offline-disables-outgoing-and-add", ![[icon valueForKey:@"movable"] boolValue] && ![[view valueForKey:@"chooseButton"] isEnabled], nil);
    [drag.draggingPasteboard releaseGlobally];
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        NSDictionary *environment = NSProcessInfo.processInfo.environment;
        if (![environment[@"GITHUB_ACTIONS"] isEqual:@"true"] || ![environment[@"RUNNER_ENVIRONMENT"] isEqual:@"github-hosted"] || argc != 2) {
            fprintf(stderr, "REFUSED: only disposable GitHub-hosted macOS may execute display QA.\n"); return 64;
        }
        Evidence = [NSString stringWithUTF8String:argv[1]];
        [[NSFileManager defaultManager] createDirectoryAtPath:Evidence withIntermediateDirectories:YES attributes:nil error:nil];
        Checks = [NSMutableArray array]; Owned = [NSMutableArray array];
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSApp finishLaunching];
        YMDisplayTopology *topology = [YMDisplayTopology new]; NSError *error = nil;
        YMDisplayTopologySnapshot *initial = [topology captureSnapshotWithError:&error];
        NSArray *initialIndependent = Inventory();
        if (!initial || initialIndependent.count == 0 || !VDVirtualDisplay.isAPIAvailable) {
            Block(@"runner-preflight", error.localizedDescription ?: @"No usable graphical session/private API"); return 78;
        }
        FixtureWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(40,40,220,120) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        FixtureWindow.title = @"yomado display CI fixture"; [FixtureWindow orderFront:nil];
        InitialWindowFrame = FixtureWindow.frame;
        Observe(@"initial");
        @try {
            CheckWorkspaceAdmissionUI();
            // Fixture A is an older output when target and sibling are added.
            VDVirtualDisplay *a = Make(1280,720,NO); if (!a) @throw [NSException exceptionWithName:@"Fixture" reason:@"A missing" userInfo:nil];
            if (!Configure(topology,a,initial,@"setup-old-output")) @throw [NSException exceptionWithName:@"Fixture" reason:@"A unavailable" userInfo:nil];
            Check(@"setup-preserved-original",Preserved(initialIndependent,Inventory()),nil);
            YMDisplayTopologySnapshot *baseline = [topology captureSnapshotWithError:&error];
            NSArray *before = Inventory();
            VDVirtualDisplay *target = Make(1280,720,NO); if (!target) @throw [NSException exceptionWithName:@"Fixture" reason:@"target missing" userInfo:nil];
            id controller = [[NSClassFromString(@"ADController") alloc] init];
            [controller setValue:topology forKey:@"displayTopology"];
            id profile = Profile(target);
            Check(@"admission-preparing-rejected",![controller canMoveIntoProfile:profile],nil);
            BOOL valid = Configure(topology,target,baseline,@"append-extended");
            Check(@"append-preserved-independent",Preserved(before,Inventory()),nil);
            [profile setValue:@(valid) forKey:@"topologyVerified"];
            Check(@"admission-verified-extended-accepted",[controller canMoveIntoProfile:profile],nil);
            [controller setValue:baseline forKey:@"topologyRecoverySnapshot"];
            Check(@"admission-recovery-pending-rejected",![controller canMoveIntoProfile:profile],nil);
            [controller setValue:nil forKey:@"topologyRecoverySnapshot"];
            YMDisplayTopologySnapshot *withTarget = [topology captureSnapshotWithError:&error];
            NSArray *beforeSibling = Inventory();
            VDVirtualDisplay *sibling = Make(960,540,YES); if (!sibling) @throw [NSException exceptionWithName:@"Fixture" reason:@"sibling missing" userInfo:nil];
            Configure(topology,sibling,withTarget,@"append-hidpi-sibling");
            Check(@"sibling-preserved-independent",Preserved(beforeSibling,Inventory()),nil);
            RemoveAndRestore(topology,sibling,withTarget,beforeSibling,@"remove-sibling");
            Check(@"survivor-admission-kept",[controller canMoveIntoProfile:profile],nil);

            if (Mirror(target.displayID,a.displayID)) {
                Observe(@"new-target-mirrored");
                Check(@"admission-mirrored-target-rejected",![controller canMoveIntoProfile:profile],nil);
                Configure(topology,target,baseline,@"unmirror-new-target-only");
                Check(@"unmirror-preserved-original-independent",Preserved(before,Inventory()),nil);
                Check(@"unmirror-admission-restored",[controller canMoveIntoProfile:profile],nil);
            } else Block(@"new-target-mirror-scenario",@"CoreGraphics did not establish the requested mirror relationship.");
            RemoveAndRestore(topology,target,baseline,before,@"remove-target");
            Check(@"admission-destroyed-target-rejected",![controller canMoveIntoProfile:profile],nil);

            // Preserve an existing mirror pair of fixtures, not the runner's own display.
            VDVirtualDisplay *b = Make(1280,720,NO); if (!b) @throw [NSException exceptionWithName:@"Fixture" reason:@"B missing" userInfo:nil];
            Configure(topology,b,baseline,@"setup-existing-mirror-follower");
            if (Mirror(b.displayID,a.displayID)) {
                YMDisplayTopologySnapshot *mirrored = [topology captureSnapshotWithError:&error]; NSArray *mirrorBefore = Inventory();
                Observe(@"preexisting-mirror-baseline");
                VDVirtualDisplay *third = Make(800,600,NO);
                if (third) {
                    Configure(topology,third,mirrored,@"append-preserves-preexisting-mirror");
                    Check(@"existing-mirror-unchanged-independent",Preserved(mirrorBefore,Inventory()),nil);
                    RemoveAndRestore(topology,third,mirrored,mirrorBefore,@"remove-from-mirrored-baseline");
                }
            } else Block(@"existing-mirror-preservation-scenario",@"CoreGraphics did not establish fixture mirror pair.");
            RemoveAndRestore(topology,b,baseline,before,@"remove-mirror-fixture");

            VDVirtualDisplay *failed = Make(800,600,NO);
            if (failed) {
                Configure(topology,failed,baseline,@"before-deliberate-drift");
                YMDisplayTopologySnapshot *driftBaseline = [topology captureSnapshotWithError:&error];
                Check(@"pre-drift-complete-topology-verifies", [topology verifySnapshot:driftBaseline error:&error], nil);
                CGRect old = CGDisplayBounds(a.displayID);
                BOOL moved = Move(a.displayID,(int32_t)old.origin.x,(int32_t)old.origin.y + 96);
                Check(@"deliberate-origin-drift-applied",moved && CGDisplayBounds(a.displayID).origin.y == old.origin.y+96,nil);
                Check(@"production-verifier-detects-old-output-drift",![topology verifySnapshot:driftBaseline error:&error],nil);
                Observe(@"deliberate-drift-before-rollback");
                RemoveAndRestore(topology,failed,baseline,before,@"rollback-after-validation-drift");
            }
            VDVirtualDisplay *wrong = Make(800,600,NO);
            if (wrong) {
                error = nil;
                BOOL accepted = [topology configureAndVerifyNewDisplay:wrong.displayID width:801 height:600 hiDPI:NO baseline:baseline error:&error];
                Check(@"incorrect-expected-dimensions-rejected",!accepted,error.localizedDescription);
                id wrongProfile = Profile(wrong); [wrongProfile setValue:@801 forKey:@"width"]; [wrongProfile setValue:@YES forKey:@"topologyVerified"];
                Check(@"admission-wrong-live-dimensions-rejected",![controller canMoveIntoProfile:wrongProfile],nil);
                RemoveAndRestore(topology,wrong,baseline,before,@"rollback-after-dimension-mismatch");
            }
            Check(@"old-primary-window-unchanged",NSEqualRects(InitialWindowFrame,FixtureWindow.frame),nil);
        } @catch (NSException *exception) {
            Check(@"unhandled-scenario-exception",NO,exception.name);
        } @finally {
            for (VDVirtualDisplay *d in Owned.reverseObjectEnumerator) if (d.isCreated) [d destroy];
            Pump(1.0); error = nil;
            BOOL restored = [topology restoreAndVerifySnapshot:initial excludingDisplayID:0 error:&error];
            Check(@"final-baseline-restored",restored,error.localizedDescription);
            Check(@"final-independent-inventory-identical",[initialIndependent isEqual:Inventory()],nil);
            Observe(@"final-restored"); [FixtureWindow orderOut:nil];
        }
        NSUInteger failed = 0, passed = 0;
        for (NSDictionary *r in Checks) if (r[@"passed"]) [r[@"passed"] boolValue] ? passed++ : failed++;
        Save(@"summary.json",@{@"passed":@(passed),@"failed":@(failed),@"blocked":@(Blocked),
            @"realCoreGraphics":@YES,@"productionAdmissionMethod":@YES,@"productionViewCallbacks":@YES,@"realMouseDragGesture":@NO,@"displayLinkHardware":@NO,
            @"localDesktopTouched":@NO,@"os":NSProcessInfo.processInfo.operatingSystemVersionString});
        return failed ? 1 : Blocked ? 78 : 0;
    }
}
