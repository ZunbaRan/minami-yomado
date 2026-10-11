#import <Foundation/Foundation.h>
#import "WindowRecoveryPolicy.h"
#include <stdio.h>

static NSUInteger checks, failures;
static NSString * const OriginalUUID = @"F23BBD72-A22F-4388-B27A-5A3B2B2C9C52";
static NSString * const OtherUUID = @"D411762D-73E9-4C94-B110-CBE862B52F37";

static void Check(BOOL condition, NSString *description) {
    checks++;
    if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", description.UTF8String); }
}

static NSDictionary *Frame(double x, double y, double width, double height) {
    return @{@"x": @(x), @"y": @(y), @"width": @(width), @"height": @(height)};
}

static NSMutableDictionary *Display(NSString *uuid, NSUInteger identifier, BOOL virtualDisplay,
                                    BOOL main, NSDictionary *bounds) {
    return [@{@"displayUUID": uuid, @"displayID": @(identifier), @"isVirtual": @(virtualDisplay),
              @"isMain": @(main), @"isActive": @YES, @"isOnline": @YES, @"bounds": bounds} mutableCopy];
}

static void PlacementAndPersistence(void) {
    NSMutableDictionary *original = Display(OriginalUUID, 2, NO, YES, Frame(-1920, 0, 1920, 1080));
    NSMutableDictionary *other = Display(OtherUUID, 4, NO, NO, Frame(0, 0, 1920, 1080));
    NSDictionary *virtualDisplay = Display(@"", 6, YES, NO, Frame(1920, 0, 1920, 1080));
    NSArray *snapshot = @[original, other, virtualDisplay];
    NSDictionary *checkpoint = YMRecoveryCheckpointForFrame(YMRecoveryWeChatBundleID,
        Frame(-1800, 80, 800, 700), snapshot, NO);
    Check(checkpoint != nil && [checkpoint[@"displayUUID"] isEqual:OriginalUUID], @"physical placement records stable original display");
    Check([checkpoint[@"window"] isEqual:Frame(120, 80, 800, 700)], @"checkpoint geometry is relative to original display");
    Check(!YMRecoveryCheckpointForFrame(YMRecoveryWeChatBundleID, Frame(2000, 80, 800, 700), snapshot, NO),
          @"virtual placement cannot overwrite physical checkpoint");
    Check(!YMRecoveryCheckpointForFrame(@"com.example.other", Frame(-1800, 80, 800, 700), snapshot, NO),
          @"only WeChat is supported");
    Check(!YMRecoveryCheckpointForFrame(YMRecoveryWeChatBundleID, Frame(1820, 80, 200, 700), snapshot, NO),
          @"physical and virtual overlap tie conservatively rejects checkpoint");
    Check(!YMRecoveryCheckpointForFrame(YMRecoveryWeChatBundleID, Frame(10000, 80, 800, 700), snapshot, NO),
          @"offscreen window cannot overwrite checkpoint");
    Check([YMRecoveryRestoreFrame(checkpoint, snapshot) isEqual:Frame(-1800, 80, 800, 700)], @"restore reuses safe original geometry");
    original[@"bounds"] = Frame(-2560, 200, 2560, 1440);
    Check([YMRecoveryRestoreFrame(checkpoint, snapshot) isEqual:Frame(-2440, 280, 800, 700)],
          @"display rearrangement uses UUID and relative offset, not stale global coordinates");
    other[@"isMain"] = @YES;
    Check([YMRecoveryRestoreDisplay(checkpoint, @[other, virtualDisplay])[@"displayID"] isEqual:@4],
          @"missing original display falls back to current physical main");
    Check([YMRecoveryRestoreFrame(checkpoint, @[other, virtualDisplay]) isEqual:Frame(120, 80, 800, 700)],
          @"missing original display geometry is clamped to fallback physical display");
    NSDictionary *small = Display(OtherUUID, 4, NO, YES, Frame(200, -200, 640, 480));
    Check([YMRecoveryRestoreFrame(checkpoint, @[small]) isEqual:Frame(200, -168, 640, 448)],
          @"oversized window remains fully reachable including menu-bar inset");
    Check(!YMRecoveryRestoreDisplay(checkpoint, @[virtualDisplay]), @"no physical output prevents recovery target selection");
    original[@"isActive"] = @NO;
    other[@"isOnline"] = @NO;
    Check(!YMRecoveryRestoreFrame(checkpoint, snapshot), @"inactive and offline physical screens are not recovery targets");

    NSMutableDictionary *tainted = [checkpoint mutableCopy];
    tainted[@"windowTitle"] = @"private title";
    tainted[@"chatText"] = @"private message";
    tainted[@"contacts"] = @[@"private contact"];
    tainted[@"serialNumber"] = @1234;
    tainted[@"password"] = @"not retained";
    tainted[@"screenshot"] = @"not retained";
    NSMutableDictionary *taintedGeometry = [checkpoint[@"window"] mutableCopy];
    taintedGeometry[@"title"] = @"not retained"; tainted[@"window"] = taintedGeometry;
    NSDictionary *safe = YMRecoveryCanonicalCheckpoint(tainted);
    Check(safe.count == 5 && [safe isEqual:checkpoint], @"persistent whitelist discards all private fields including nested fields");
    NSData *safeData = [NSJSONSerialization dataWithJSONObject:safe options:0 error:nil];
    NSString *encoded = [[NSString alloc] initWithData:safeData encoding:NSUTF8StringEncoding];
    Check([encoded rangeOfString:@"private"].location == NSNotFound &&
          [encoded rangeOfString:@"password"].location == NSNotFound, @"serialized checkpoint excludes all supplied private text");
    tainted[@"displayUUID"] = @"invalid";
    Check(!YMRecoveryCanonicalCheckpoint(tainted), @"invalid UUID is rejected");
    tainted = [checkpoint mutableCopy]; tainted[@"bundleID"] = @"com.example.other";
    Check(!YMRecoveryCanonicalCheckpoint(tainted), @"foreign application checkpoint is rejected on load");
    tainted = [checkpoint mutableCopy]; tainted[@"schemaVersion"] = @2;
    Check(!YMRecoveryCanonicalCheckpoint(tainted), @"unknown schema is rejected on load");
    Check(!YMRecoveryGeometry(Frame(NAN, 0, 800, 700)) && !YMRecoveryGeometry(Frame(0, 0, INFINITY, 700)) &&
          !YMRecoveryGeometry(Frame(0, 0, 0, 700)), @"invalid or non-finite geometry is rejected");
    Check(YMRecoveryGeometry(Frame(-3000, -200, 800, 700)) != nil, @"valid negative desktop coordinates remain supported");
}

static void ObservedGeometry(void) {
    NSDictionary *physical = Display(OriginalUUID, 2, NO, YES, Frame(0, 0, 1920, 1080));
    NSDictionary *virtualDisplay = Display(@"", 6, YES, NO, Frame(1920, 0, 1920, 1080));
    NSDictionary *requested = Frame(100, 80, 800, 700);
    Check(YMRecoveryObservedFrameIsAccessible(requested, requested, physical), @"readback accepts the complete intended physical placement");
    Check(!YMRecoveryObservedFrameIsAccessible(Frame(2020, 80, 800, 700), requested, physical), @"AX success with window still on virtual cannot clear pending recovery");
    Check(!YMRecoveryObservedFrameIsAccessible(Frame(100, 80, 800, 700), Frame(2020, 80, 800, 700), virtualDisplay), @"unapplied move cannot claim owned virtual display success");
    Check(!YMRecoveryObservedFrameIsAccessible(Frame(1500, 80, 800, 700), requested, physical), @"partly clipped physical window is not verified as accessible");
    Check(!YMRecoveryObservedFrameIsAccessible(Frame(100, 0, 800, 700), requested, physical), @"title bar hidden under menu bar is rejected");
    Check(YMRecoveryObservedFrameIsAccessible(Frame(100, 80, 1000, 800), requested, physical), @"application minimum size is accepted when complete frame fits current screen");
    Check(YMRecoveryObservedFrameIsAccessible(Frame(100, 80, 250, 343), Frame(100, 80, 250, 343), physical), @"replacement login window can keep its own fixed size");
    Check(!YMRecoveryObservedFrameIsAccessible(Frame(100, 80, 5, 5), requested, physical), @"implausibly collapsed main window does not establish success");
    Check(!YMRecoveryObservedFrameIsAccessible(Frame(NAN, 80, 800, 700), requested, physical), @"invalid readback cannot establish success");
}

static void RecoveryGuardrails(void) {
    Check(YMRecoveryDialogRoleSupported(@"AXWindow", @"AXDialog"), @"dialog subrole may be inspected");
    Check(YMRecoveryDialogRoleSupported(@"AXWindow", @"AXSystemDialog"), @"system dialog subrole may be inspected");
    Check(YMRecoveryDialogRoleSupported(@"AXSheet", nil), @"direct sheet role may be inspected");
    Check(!YMRecoveryDialogRoleSupported(@"AXWindow", @"AXStandardWindow"), @"ordinary chat window role is excluded even when small");
    Check(!YMRecoveryDialogRoleSupported(@"AXGroup", nil), @"arbitrary group cannot become a safety dialog");
    Check(YMRecoveryIsSupportedSafetyText(@"为了你的账号安全，请重新登录。"), @"supported exact security prompt is recognized");
    Check(YMRecoveryIsSupportedSafetyText(@"提示 为了你的账号安全，请重新登录。"), @"observed title-and-message security label is recognized exactly");
    Check(YMRecoveryIsSupportedSafetyText(@"\n需在手机上完成登录\n"), @"supported exact phone-login prompt accepts surrounding whitespace");
    Check(!YMRecoveryIsSupportedSafetyText(@"有人发给我：为了你的账号安全，请重新登录。"), @"quotation or message containing the phrase is not a safety prompt");
    Check(!YMRecoveryIsSupportedSafetyText(@"some other dialog") && !YMRecoveryIsSupportedSafetyText(@17), @"unknown text is not a safety prompt");
    Check(!YMRecoveryCanPoll(NO, NO, 0, 10), @"no tracked move means no background AX polling");
    Check(!YMRecoveryCanPoll(YES, NO, 10, 14.9), @"polling cannot run more often than once per five seconds");
    Check(YMRecoveryCanPoll(YES, NO, 10, 15), @"eligible tracked move may be checked after the observation interval");
    Check(!YMRecoveryCanPoll(YES, YES, 10, 15) && !YMRecoveryCanPoll(YES, YES, 10, 100000),
          @"paused state latches after failure and prevents any timed retry");
    Check(!YMRecoveryCanPoll(YES, NO, 10, 9) && !YMRecoveryCanPoll(YES, NO, NAN, 20),
          @"clock reversal and invalid times cannot trigger rapid polling");
}

int main(void) {
    @autoreleasepool {
        PlacementAndPersistence(); ObservedGeometry(); RecoveryGuardrails();
        printf("Window recovery: %lu checks, %lu failures; no GUI, AX or displays accessed.\n",
               (unsigned long)checks, (unsigned long)failures);
        return failures ? 1 : 0;
    }
}
