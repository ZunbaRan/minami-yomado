#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <errno.h>
#include <math.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>

// Independent recovery process. It owns no virtual display and changes only
// display IDs recorded by the parent in an armed state file.
typedef CGError (*EnableDisplayFunction)(CGDisplayConfigRef,
                                         CGDirectDisplayID, bool);

static BOOL ParentAlive(pid_t parentPID) {
    return kill(parentPID, 0) == 0 || errno == EPERM;
}

static BOOL IsNumber(id value) {
    return [value isKindOfClass:[NSNumber class]];
}

static BOOL DisplayIDValue(id value, BOOL allowZero, CGDirectDisplayID *result) {
    if (!IsNumber(value)) return NO;
    double number = [value doubleValue];
    if (!isfinite(number) || floor(number) != number ||
        number < (allowZero ? 0 : 1) || number > UINT32_MAX) return NO;
    *result = (CGDirectDisplayID)number;
    return YES;
}

static NSDictionary *ReadState(NSString *path, pid_t parentPID) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || data.length > 65536) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![object isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *state = object;
    if (!IsNumber(state[@"parentPID"]) ||
        [state[@"parentPID"] longLongValue] != parentPID ||
        !IsNumber(state[@"heartbeat"]) ||
        !isfinite([state[@"heartbeat"] doubleValue]) ||
        !IsNumber(state[@"armed"]) || !IsNumber(state[@"end"])) return nil;

    // An unarmed state is also the shutdown handshake; it need not contain
    // recovery metadata because it never leads to a display mutation.
    if (![state[@"armed"] boolValue]) return state;
    CGDirectDisplayID virtualID = 0;
    if (!DisplayIDValue(state[@"virtualID"], NO, &virtualID)) return nil;
    id rawTargets = state[@"targets"];
    if (![rawTargets isKindOfClass:[NSArray class]] ||
        [rawTargets count] == 0 || [rawTargets count] > 64) return nil;
    NSMutableOrderedSet<NSNumber *> *targets = [NSMutableOrderedSet orderedSet];
    for (id value in rawTargets) {
        CGDirectDisplayID displayID = 0;
        if (!DisplayIDValue(value, NO, &displayID) || displayID == virtualID)
            return nil;
        [targets addObject:@(displayID)];
    }
    NSMutableDictionary *validated = [state mutableCopy];
    validated[@"targets"] = targets.array;
    return validated;
}

static CGDisplayCount CopyActiveDisplays(CGDirectDisplayID displayIDs[64]) {
    CGDisplayCount count = 0;
    CGError error = CGGetActiveDisplayList(64, displayIDs, &count);
    return error == kCGErrorSuccess ? MIN(count, (CGDisplayCount)64) : 0;
}

static BOOL DisplayInActiveList(CGDirectDisplayID displayID,
                                const CGDirectDisplayID *displayIDs,
                                CGDisplayCount count) {
    for (CGDisplayCount index = 0; index < count; ++index) {
        if (displayIDs[index] == displayID) return YES;
    }
    return NO;
}

static BOOL DisplayActive(CGDirectDisplayID displayID) {
    // Some legacy per-ID queries return a fallback display for a deleted ID.
    // Membership in the explicit active list is the actual existence check.
    CGDirectDisplayID displayIDs[64] = {0};
    CGDisplayCount count = CopyActiveDisplays(displayIDs);
    return DisplayInActiveList(displayID, displayIDs, count);
}

static NSUInteger ActiveDisplayCount(void) {
    CGDirectDisplayID displayIDs[64] = {0};
    return CopyActiveDisplays(displayIDs);
}

static BOOL AllTargetsActive(NSArray<NSNumber *> *targets) {
    CGDirectDisplayID displayIDs[64] = {0};
    CGDisplayCount count = CopyActiveDisplays(displayIDs);
    for (NSNumber *value in targets) {
        if (!DisplayInActiveList(value.unsignedIntValue, displayIDs, count)) return NO;
    }
    return targets.count != 0;
}

static BOOL AnyTargetActive(NSArray<NSNumber *> *targets) {
    // The parent records physical displays only. Checking our own target IDs
    // avoids mistaking a different application's virtual display for recovery.
    CGDirectDisplayID displayIDs[64] = {0};
    CGDisplayCount count = CopyActiveDisplays(displayIDs);
    for (NSNumber *value in targets) {
        if (DisplayInActiveList(value.unsignedIntValue, displayIDs, count)) return YES;
    }
    return NO;
}

static BOOL WriteMarker(NSString *path, NSString *suffix, NSString *text) {
    NSError *error = nil;
    BOOL success = [text writeToFile:[path stringByAppendingString:suffix]
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:&error];
    if (!success) NSLog(@"Recovery marker could not be written: %@ (%ld)", error.domain, (long)error.code);
    return success;
}

static EnableDisplayFunction LoadEnableFunction(void **frameworkHandle) {
    *frameworkHandle = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        RTLD_LAZY | RTLD_LOCAL);
    void *symbol = *frameworkHandle
        ? dlsym(*frameworkHandle, "SLSConfigureDisplayEnabled") : NULL;
    if (!symbol && *frameworkHandle)
        symbol = dlsym(*frameworkHandle, "CGSConfigureDisplayEnabled");
    if (!symbol) symbol = dlsym(RTLD_DEFAULT, "CGSConfigureDisplayEnabled");
    return (EnableDisplayFunction)symbol;
}

static CGError EnableTargets(EnableDisplayFunction enable,
                             NSArray<NSNumber *> *targets) {
    CGDisplayConfigRef config = NULL;
    CGError error = CGBeginDisplayConfiguration(&config);
    if (error != kCGErrorSuccess || !config) return error;
    CGError firstError = kCGErrorSuccess;
    for (NSNumber *value in targets) {
        CGDirectDisplayID displayID = value.unsignedIntValue;
        // Enable even if the active list already reports the target. This is
        // an idempotent recovery request and never disables another display.
        CGError result = enable(config, displayID, true);
        if (result != kCGErrorSuccess && firstError == kCGErrorSuccess)
            firstError = result;
    }
    // The configuration is invalid after completion, even if completion fails.
    CGError completion = CGCompleteDisplayConfiguration(config,
                                                         kCGConfigureForSession);
    return completion != kCGErrorSuccess ? completion : firstError;
}

static int Recover(NSString *path, NSDictionary *state, NSString *reason) {
    NSArray<NSNumber *> *targets = state[@"targets"];
    void *frameworkHandle = NULL;
    EnableDisplayFunction enable = LoadEnableFunction(&frameworkHandle);
    if (!enable) {
        WriteMarker(path, @".error", @"The display-enable API is unavailable; recovery was not performed.\n");
        return 2;
    }

    NSTimeInterval started = NSDate.date.timeIntervalSince1970;
    CGError lastError = kCGErrorSuccess;
    NSUInteger attempts = 0;
    do {
        @autoreleasepool {
            ++attempts;
            lastError = EnableTargets(enable, targets);
            // WindowServer applies topology asynchronously. A one-second
            // settle also spaces retries and allows the physical panel to wake.
            sleep(1);
            if (AllTargetsActive(targets)) {
                NSString *message = [NSString stringWithFormat:
                    @"Restored all armed physical displays (%@); attempts=%lu.\n",
                    reason, (unsigned long)attempts];
                BOOL marked = WriteMarker(path, @".restored", message);
                if (frameworkHandle) dlclose(frameworkHandle);
                return marked ? 0 : 3;
            }
            // Three attempts are enough if a physical target has recovered.
            // Keep trying for at most 60 seconds when none is active, because
            // stopping immediately could leave the user without a visible panel.
            if (attempts >= 3 && AnyTargetActive(targets)) break;
        }
    } while (NSDate.date.timeIntervalSince1970 - started < 60.0);

    NSString *message = [NSString stringWithFormat:
        @"Recovery incomplete (%@); attempts=%lu, CGError=%d, physicalTargetActive=%@.\n",
        reason, (unsigned long)attempts, (int)lastError,
        AnyTargetActive(targets) ? @"yes" : @"no"];
    WriteMarker(path, @".error", message);
    if (frameworkHandle) dlclose(frameworkHandle);
    return 2;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) {
            fprintf(stderr, "Usage: display-watchdog <statepath> <parentPID>\n");
            return 64;
        }
        char *end = NULL;
        errno = 0;
        long parsedPID = strtol(argv[2], &end, 10);
        if (errno || !end || *end || parsedPID <= 1 || parsedPID > INT32_MAX)
            return 64;
        pid_t parentPID = (pid_t)parsedPID;
        NSString *path = [NSString stringWithUTF8String:argv[1]];
        if (!path.length) return 64;
        NSDictionary *initialState = ReadState(path, parentPID);
        if (!initialState) {
            WriteMarker(path, @".error", @"Initial watchdog state is missing or invalid.\n");
            return 65;
        }
        if (!ParentAlive(parentPID) && ![initialState[@"armed"] boolValue])
            return 0;
        void *initialFrameworkHandle = NULL;
        EnableDisplayFunction initialEnable = LoadEnableFunction(&initialFrameworkHandle);
        if (!initialEnable) {
            WriteMarker(path, @".error", @"The display-enable API is unavailable; watchdog is not ready.\n");
            return 2;
        }
        if (initialFrameworkHandle) dlclose(initialFrameworkHandle);
        NSString *ready = [NSString stringWithFormat:@"Ready: helperPID=%d, parentPID=%d.\n",
                            (int)getpid(), (int)parentPID];
        if (!WriteMarker(path, @".ready", ready)) return 3;
        NSDictionary *armedState = [initialState[@"armed"] boolValue] ? initialState : nil;

        for (;;) {
            @autoreleasepool {
                NSDictionary *state = ReadState(path, parentPID);
                BOOL alive = ParentAlive(parentPID);
                if (state) {
                    if (![state[@"armed"] boolValue]) {
                        armedState = nil;
                        if ([state[@"end"] boolValue] || !alive) return 0;
                    } else {
                        armedState = state;
                    }
                }
                if (!armedState) {
                    if (!alive) return 0;
                } else {
                    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
                    NSTimeInterval heartbeat = [armedState[@"heartbeat"] doubleValue];
                    CGDirectDisplayID virtualID = [armedState[@"virtualID"] unsignedIntValue];
                    NSString *reason = nil;
                    if (!alive) reason = @"parent exited";
                    else if (now - heartbeat > 12.0) reason = @"heartbeat expired";
                    else if (!DisplayActive(virtualID)) reason = @"virtual display unavailable";
                    else if (ActiveDisplayCount() == 0) reason = @"no active displays";
                    if (reason) return Recover(path, armedState, reason);
                }
            }
            sleep(1);
        }
    }
}
