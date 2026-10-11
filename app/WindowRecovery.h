#ifndef YOMADO_WINDOW_RECOVERY_H
#define YOMADO_WINDOW_RECOVERY_H

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const YMWindowRecoveryErrorDomain;

// WeChat-only window geometry recovery. No account state, window titles,
// conversation contents or screenshots are read into the checkpoint.
// All methods must be called on the main thread. Do not instantiate this
// manager in the fixture-only UI preview path.
@interface YMWindowRecovery : NSObject
- (instancetype)initWithCheckpointURL:(nullable NSURL *)URL;
@property(nonatomic, copy, readonly) NSString *statusText;
@property(nonatomic, readonly) BOOL accessibilityTrusted;
@property(nonatomic, readonly) BOOL hasCheckpoint;
@property(nonatomic, readonly) BOOL trackedWindowOnVirtual;
@property(nonatomic, readonly) BOOL needsRestoreBeforeRemovingVirtualDisplay;
@property(nonatomic, readonly) BOOL automaticRecoveryPaused;
@property(nonatomic, readonly) BOOL canMove;
@property(nonatomic, readonly) BOOL canRestore;

// Read-only display inventory injection; never reconfigures a display. Stable
// UUIDs are resolved from current display IDs if not supplied by the caller.
- (void)refreshWithVirtualDisplayID:(CGDirectDisplayID)displayID
                  displaySnapshot:(NSArray<NSDictionary *> *)snapshot;

// Register the Accessibility request and open its System Settings page only
// after an explicit click. The user must grant permission in System Settings.
// YES means the settings URL opened, not that permission has been granted.
- (BOOL)openAccessibilitySettings:(NSError * _Nullable * _Nullable)error;
- (BOOL)captureWeChatPlacement:(NSError * _Nullable * _Nullable)error;
// Save a physical checkpoint successfully before moving the single main
// WeChat window. A virtual position never overwrites the physical checkpoint.
- (BOOL)moveWeChatToVirtual:(NSError * _Nullable * _Nullable)error;
// A physical-screen tile drag must match the selected WeChat main window's
// dominant physical display before any checkpoint is written or window moved.
// Zero preserves the original whole-main-window behavior for an external drop.
- (BOOL)moveWeChatToVirtualFromDisplayID:(CGDirectDisplayID)sourceDisplayID
                                  error:(NSError * _Nullable * _Nullable)error;
- (BOOL)restoreWeChat:(NSError * _Nullable * _Nullable)error;
// At most one AX check per five seconds while a tracked move is pending.
// Examines only AXDialog/AXSystemDialog and directly attached sheets, never
// an ordinary chat window's descendants. Exact supported security prompts
// cause restoration only; no clicks, login, app relaunch or repeated retries.
// Unsupported dialog roles require the manual restore action.
- (BOOL)pollForRecovery:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
#endif
