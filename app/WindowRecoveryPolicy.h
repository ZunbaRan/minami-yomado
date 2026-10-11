#ifndef YOMADO_WINDOW_RECOVERY_POLICY_H
#define YOMADO_WINDOW_RECOVERY_POLICY_H

#import <Foundation/Foundation.h>
#include <math.h>

// Pure geometry and persistence policy. This header does not access displays,
// Accessibility, application windows, or private application contents.
static NSString * const YMRecoveryWeChatBundleID = @"com.tencent.xinWeChat";

static inline BOOL YMRecoverySupportedBundle(id bundleID) {
    return [bundleID isKindOfClass:NSString.class] && [bundleID isEqualToString:YMRecoveryWeChatBundleID];
}

static inline BOOL YMRecoveryFiniteNumber(id value) {
    return [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]);
}

static inline NSDictionary *YMRecoveryGeometry(id input) {
    if (![input isKindOfClass:NSDictionary.class]) return nil;
    for (NSString *key in @[@"x", @"y", @"width", @"height"]) {
        if (!YMRecoveryFiniteNumber(input[key])) return nil;
    }
    double x = [input[@"x"] doubleValue], y = [input[@"y"] doubleValue];
    double width = [input[@"width"] doubleValue], height = [input[@"height"] doubleValue];
    if (fabs(x) > 1000000 || fabs(y) > 1000000 || width < 1 || height < 1 ||
        width > 100000 || height > 100000 || !isfinite(x + width) || !isfinite(y + height)) return nil;
    return @{@"x": @(x), @"y": @(y), @"width": @(width), @"height": @(height)};
}

// A whitelist is used both before writing and after loading. Extra fields,
// including titles, account data and device metadata, are always discarded.
// x/y are offsets from the original physical display's top-left corner.
static inline NSDictionary *YMRecoveryCanonicalCheckpoint(id input) {
    if (![input isKindOfClass:NSDictionary.class] || !YMRecoverySupportedBundle(input[@"bundleID"]) ||
        ![input[@"schemaVersion"] isKindOfClass:NSNumber.class] || [input[@"schemaVersion"] integerValue] != 1 ||
        ![input[@"displayUUID"] isKindOfClass:NSString.class] ||
        ![[NSUUID alloc] initWithUUIDString:input[@"displayUUID"]] ||
        ![input[@"recoveryPending"] isKindOfClass:NSNumber.class]) return nil;
    NSDictionary *geometry = YMRecoveryGeometry(input[@"window"]);
    if (!geometry) return nil;
    return @{@"schemaVersion": @1, @"bundleID": YMRecoveryWeChatBundleID,
             @"displayUUID": [input[@"displayUUID"] copy], @"window": geometry,
             @"recoveryPending": @([input[@"recoveryPending"] boolValue])};
}

static inline BOOL YMRecoveryUsableDisplay(NSDictionary *display) {
    return [display isKindOfClass:NSDictionary.class] &&
        [display[@"isActive"] isKindOfClass:NSNumber.class] && [display[@"isActive"] boolValue] &&
        [display[@"isOnline"] isKindOfClass:NSNumber.class] && [display[@"isOnline"] boolValue] &&
        [display[@"isVirtual"] isKindOfClass:NSNumber.class] &&
        YMRecoveryGeometry(display[@"bounds"]) != nil;
}

static inline double YMRecoveryIntersectionArea(NSDictionary *a, NSDictionary *b) {
    double left = fmax([a[@"x"] doubleValue], [b[@"x"] doubleValue]);
    double top = fmax([a[@"y"] doubleValue], [b[@"y"] doubleValue]);
    double right = fmin([a[@"x"] doubleValue] + [a[@"width"] doubleValue],
                       [b[@"x"] doubleValue] + [b[@"width"] doubleValue]);
    double bottom = fmin([a[@"y"] doubleValue] + [a[@"height"] doubleValue],
                        [b[@"y"] doubleValue] + [b[@"height"] doubleValue]);
    return fmax(0, right - left) * fmax(0, bottom - top);
}

// The dominant display must be a physical display. A virtual placement can
// never replace the remembered physical checkpoint, even after an app restart.
static inline NSDictionary *YMRecoveryDominantDisplay(NSDictionary *frame, NSArray *snapshot) {
    if (!YMRecoveryGeometry(frame) || ![snapshot isKindOfClass:NSArray.class]) return nil;
    NSDictionary *best = nil;
    double bestArea = 0;
    for (id display in snapshot) {
        if (!YMRecoveryUsableDisplay(display)) continue;
        double area = YMRecoveryIntersectionArea(frame, display[@"bounds"]);
        // On ties, choose virtual conservatively so capture cannot overwrite
        // a physical checkpoint from a window straddling a display boundary.
        if (area > bestArea || (area > 0 && area == bestArea && [display[@"isVirtual"] boolValue])) {
            best = display; bestArea = area;
        }
    }
    return best;
}

static inline NSDictionary *YMRecoveryCheckpointForFrame(NSString *bundleID, NSDictionary *frame,
                                                          NSArray *snapshot, BOOL pending) {
    if (!YMRecoverySupportedBundle(bundleID)) return nil;
    NSDictionary *display = YMRecoveryDominantDisplay(frame, snapshot);
    if (!display || [display[@"isVirtual"] boolValue]) return nil;
    NSDictionary *bounds = display[@"bounds"];
    NSDictionary *relative = @{@"x": @([frame[@"x"] doubleValue] - [bounds[@"x"] doubleValue]),
                               @"y": @([frame[@"y"] doubleValue] - [bounds[@"y"] doubleValue]),
                               @"width": frame[@"width"], @"height": frame[@"height"]};
    return YMRecoveryCanonicalCheckpoint(@{@"schemaVersion": @1, @"bundleID": bundleID,
        @"displayUUID": display[@"displayUUID"] ?: @"", @"window": relative, @"recoveryPending": @(pending)});
}

static inline NSDictionary *YMRecoveryRestoreDisplay(NSDictionary *checkpoint, NSArray *snapshot) {
    NSDictionary *canonical = YMRecoveryCanonicalCheckpoint(checkpoint);
    if (!canonical || ![snapshot isKindOfClass:NSArray.class]) return nil;
    NSDictionary *first = nil, *main = nil;
    for (id display in snapshot) {
        if (!YMRecoveryUsableDisplay(display) || [display[@"isVirtual"] boolValue]) continue;
        if (!first) first = display;
        if ([display[@"isMain"] boolValue]) main = display;
        if ([display[@"displayUUID"] isEqual:canonical[@"displayUUID"]]) return display;
    }
    return main ?: first;
}

// Constrain the window to one current physical display, including a top inset
// for macOS's menu bar. If the original display is missing, use physical main.
static inline NSDictionary *YMRecoveryFrameOnDisplay(NSDictionary *relative, NSDictionary *display) {
    NSDictionary *geometry = YMRecoveryGeometry(relative);
    if (!geometry || !YMRecoveryUsableDisplay(display)) return nil;
    NSDictionary *bounds = display[@"bounds"];
    double availableWidth = [bounds[@"width"] doubleValue];
    double availableHeight = [bounds[@"height"] doubleValue];
    double topInset = fmin(32, fmax(0, availableHeight - 1));
    double width = fmin([geometry[@"width"] doubleValue], availableWidth);
    double height = fmin([geometry[@"height"] doubleValue], availableHeight - topInset);
    double offsetX = fmin(fmax(0, [geometry[@"x"] doubleValue]), availableWidth - width);
    double offsetY = fmin(fmax(topInset, [geometry[@"y"] doubleValue]), availableHeight - height);
    return @{@"x": @([bounds[@"x"] doubleValue] + offsetX),
             @"y": @([bounds[@"y"] doubleValue] + offsetY), @"width": @(width), @"height": @(height)};
}

static inline NSDictionary *YMRecoveryRestoreFrame(NSDictionary *checkpoint, NSArray *snapshot) {
    NSDictionary *canonical = YMRecoveryCanonicalCheckpoint(checkpoint);
    NSDictionary *display = YMRecoveryRestoreDisplay(canonical, snapshot);
    return display ? YMRecoveryFrameOnDisplay(canonical[@"window"], display) : nil;
}

// A successful AX write is insufficient. The observed complete frame must be
// on the intended display with a reachable, reasonably sized window. This also
// allows applications to keep their own minimum dimensions when they fit.
static inline BOOL YMRecoveryObservedFrameIsAccessible(NSDictionary *actual, NSDictionary *requested,
                                                        NSDictionary *display) {
    actual = YMRecoveryGeometry(actual); requested = YMRecoveryGeometry(requested);
    if (!actual || !requested || !YMRecoveryUsableDisplay(display)) return NO;
    NSDictionary *bounds = display[@"bounds"];
    double epsilon = 2.0;
    double x = [actual[@"x"] doubleValue], y = [actual[@"y"] doubleValue];
    double width = [actual[@"width"] doubleValue], height = [actual[@"height"] doubleValue];
    double left = [bounds[@"x"] doubleValue], top = [bounds[@"y"] doubleValue];
    double right = left + [bounds[@"width"] doubleValue], bottom = top + [bounds[@"height"] doubleValue];
    return width >= fmin(160, [requested[@"width"] doubleValue]) &&
        height >= fmin(100, [requested[@"height"] doubleValue]) &&
        x >= left - epsilon && y >= top + fmin(24, [bounds[@"height"] doubleValue] - 1) - epsilon &&
        x + width <= right + epsilon && y + height <= bottom + epsilon;
}

// Detection policy accepts only explicit dialog/sheet roles and a small set of
// exact static strings. A quoted sentence or an ordinary chat window is never
// a supported security prompt.
static inline BOOL YMRecoveryDialogRoleSupported(NSString *role, NSString *subrole) {
    return [role isEqualToString:@"AXSheet"] || [subrole isEqualToString:@"AXDialog"] ||
           [subrole isEqualToString:@"AXSystemDialog"];
}

static inline BOOL YMRecoveryIsSupportedSafetyText(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] > 160) return NO;
    NSString *text = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    for (NSString *phrase in @[@"为了你的账号安全，请重新登录", @"提示 为了你的账号安全，请重新登录", @"需在手机上完成登录"]) {
        if ([text isEqualToString:phrase] || [text isEqualToString:[phrase stringByAppendingString:@"。"]] ||
            [text isEqualToString:[phrase stringByAppendingString:@"."]]) return YES;
    }
    return NO;
}

// No continuous retry after failure. The caller latches paused until an
// explicit user action succeeds. The interval also bounds background AX work.
static inline BOOL YMRecoveryCanPoll(BOOL pending, BOOL paused, NSTimeInterval lastPoll, NSTimeInterval now) {
    return pending && !paused && isfinite(lastPoll) && isfinite(now) && now - lastPoll >= 5.0;
}

#endif
