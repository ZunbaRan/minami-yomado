#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <Carbon/Carbon.h>
#import <dlfcn.h>
#import <signal.h>
#import "VDVirtualDisplay.h"
#import "LayoutPolicy.h"
#import "DiagnosticPrivacy.h"

typedef CGError (*ADEnableFunction)(CGDisplayConfigRef, CGDirectDisplayID, bool);
static ADEnableFunction EnableAPI(void) {
    static ADEnableFunction fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY);
        if (cg) fn = (ADEnableFunction)dlsym(cg, "CGSConfigureDisplayEnabled");
        if (!fn) {
            void *sl = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
            if (sl) fn = (ADEnableFunction)dlsym(sl, "SLSConfigureDisplayEnabled");
        }
    });
    return fn;
}
static BOOL ConfigureEnabled(NSArray<NSNumber *> *ids, BOOL enabled, NSString **message) {
    ADEnableFunction fn = EnableAPI();
    if (!fn) { if (message) *message = @"当前系统没有实体显示器开关接口。"; return NO; }
    CGDisplayConfigRef config = NULL;
    CGError err = CGBeginDisplayConfiguration(&config);
    if (err != kCGErrorSuccess || !config) {
        if (message) *message = [NSString stringWithFormat:@"无法开始显示设置（%d）。", err];
        return NO;
    }
    for (NSNumber *item in ids) {
        err = fn(config, item.unsignedIntValue, enabled);
        if (err != kCGErrorSuccess) {
            CGCancelDisplayConfiguration(config);
            if (message) *message = [NSString stringWithFormat:@"显示器 %@ 设置失败（%d）。", item, err];
            return NO;
        }
    }
    // This is never written into the permanent macOS display configuration.
    err = CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
    if (err != kCGErrorSuccess && message) *message = [NSString stringWithFormat:@"显示设置未完成（%d）。", err];
    return err == kCGErrorSuccess;
}
static NSArray<NSDictionary *> *DisplaySnapshot(void) { return [VDVirtualDisplay onlineDisplays]; }
static BOOL ADDisplayActive(CGDirectDisplayID ident) {
    CGDirectDisplayID ids[64] = {0}; CGDisplayCount count = 0;
    if (!ident || CGGetActiveDisplayList(64, ids, &count) != kCGErrorSuccess) return NO;
    for (CGDisplayCount i = 0; i < count; i++) if (ids[i] == ident) return YES;
    return NO;
}
static BOOL ADDisplayOnline(CGDirectDisplayID ident) {
    CGDirectDisplayID ids[64] = {0}; CGDisplayCount count = 0;
    if (!ident || CGGetOnlineDisplayList(64, ids, &count) != kCGErrorSuccess) return NO;
    for (CGDisplayCount i = 0; i < count; i++) if (ids[i] == ident) return YES;
    return NO;
}
static BOOL WaitUntil(BOOL (^predicate)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!predicate() && deadline.timeIntervalSinceNow > 0) {
        @autoreleasepool {
            NSDate *step = [NSDate dateWithTimeIntervalSinceNow:0.05];
            NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:step inMode:NSDefaultRunLoopMode dequeue:YES];
            if (event) [NSApp sendEvent:event];
            [[NSRunLoop currentRunLoop] runUntilDate:step];
        }
    }
    return predicate();
}
static NSString *JSONTextWithIdentifiers(id object, BOOL includeIdentifiers) {
    id report = includeIdentifiers ? object : YMRedactedDiagnostics(object);
    NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
}
static NSString *JSONText(id object) { return JSONTextWithIdentifiers(object, NO); }

@interface ADTestView : NSView
@property NSInteger frameNumber;
@end
@implementation ADTestView
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithCalibratedRed:0.07 green:0.11 blue:0.20 alpha:1] setFill];
    NSRectFill(self.bounds);
    NSDictionary *attrs = @{NSFontAttributeName:[NSFont systemFontOfSize:28 weight:NSFontWeightSemibold],
                            NSForegroundColorAttributeName:NSColor.whiteColor};
    [[NSString stringWithFormat:@"Yomado · frame %ld", (long)self.frameNumber]
        drawAtPoint:NSMakePoint(28, 150) withAttributes:attrs];
    [[NSColor colorWithCalibratedRed:0.24 green:0.65 blue:0.93 alpha:1] setFill];
    NSRectFill(NSMakeRect(30 + self.frameNumber * 95, 35, 70, 70));
}
- (NSData *)PNGData {
    [self displayIfNeeded];
    NSBitmapImageRep *bitmap = [self bitmapImageRepForCachingDisplayInRect:self.bounds];
    [self cacheDisplayInRect:self.bounds toBitmapImageRep:bitmap];
    return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}
@end

@interface ADController : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property NSWindow *window;
@property NSStatusItem *statusItem;
@property NSTextField *statusLabel;
@property NSTextField *inventoryLabel;
@property NSTextField *detailLabel;
@property NSPopUpButton *resolution;
@property NSPopUpButton *physicalChoice;
@property NSButton *hiDPIBox;
@property NSButton *createButton;
@property NSButton *testButton;
@property NSButton *keepButton;
@property NSButton *restoreButton;
@property VDVirtualDisplay *virtualDisplay;
@property NSArray<NSDictionary *> *originalLayout;
@property CGDirectDisplayID originalMain;
@property NSArray<NSNumber *> *targets;
@property NSTask *watchdog;
@property NSString *statePath;
@property NSTimer *heartbeatTimer;
@property BOOL armed;
@property BOOL preparing;
@property BOOL restoring;
@property BOOL recoveryRequested;
@property BOOL layoutChangedForTrial;
@property NSUInteger operationGeneration;
@property NSTimeInterval trialDeadline;
@property IOPMAssertionID systemAssertion;
@property IOPMAssertionID displayAssertion;
@property EventHotKeyRef hotkey;
@property EventHandlerRef keyHandler;
- (void)restore:(id)sender;
@end

static OSStatus RecoveryHotkey(EventHandlerCallRef next, EventRef event, void *data) {
    (void)next; (void)event;
    ADController *controller = (__bridge ADController *)data;
    [controller restore:nil];
    return noErr;
}
static NSTextField *Label(NSString *text, CGFloat size, NSFontWeight weight) {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.lineBreakMode = NSLineBreakByWordWrapping;
    return label;
}
static NSButton *ADButton(NSString *title, id target, SEL action) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.bezelStyle = NSBezelStyleRounded;
    return button;
}

@implementation ADController
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.virtualDisplay = [[VDVirtualDisplay alloc] initWithSerialNumber:0x41443101];
    self.targets = @[];
    self.systemAssertion = kIOPMNullAssertionID;
    self.displayAssertion = kIOPMNullAssertionID;
    self.statePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"Yomado-%@.json", NSUUID.UUID.UUIDString]];
    [self buildMenu];
    NSMenu *main = [[NSMenu alloc] init];
    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"Yomado" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Yomado"];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"退出 Yomado" action:@selector(quit:) keyEquivalent:@"q"];
    quitItem.target = self;
    [appMenu addItem:quitItem];
    appItem.submenu = appMenu;
    [main addItem:appItem];
    NSApp.mainMenu = main;
    [self buildWindow];
    EventTypeSpec type = { kEventClassKeyboard, kEventHotKeyPressed };
    OSStatus handlerStatus = InstallEventHandler(GetApplicationEventTarget(), RecoveryHotkey, 1, &type,
                                                (__bridge void *)self, &_keyHandler);
    EventHotKeyID hotkeyID = { 'ADsp', 1 };
    OSStatus keyStatus = RegisterEventHotKey(kVK_ANSI_R, controlKey | optionKey | cmdKey,
                                            hotkeyID, GetApplicationEventTarget(), 0, &_hotkey);
    if (handlerStatus != noErr || keyStatus != noErr) {
        self.testButton.enabled = NO;
        self.detailLabel.stringValue = @"恢复快捷键注册失败；为保留恢复途径，实体屏关闭功能已停用。";
    }
    [self updateInventory];
    [self showWindow:nil];
    self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(tick:)
                                                       userInfo:nil repeats:YES];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(systemWillSleep:)
          name:NSWorkspaceWillSleepNotification object:nil];
}
- (void)buildMenu {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"display.2" accessibilityDescription:@"Agent 虚拟屏"];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Yomado"];
    for (NSArray *row in @[@[@"打开控制面板", NSStringFromSelector(@selector(showWindow:))],
                           @[@"恢复实体显示器", NSStringFromSelector(@selector(restore:))],
                           @[@"停止并移除虚拟屏", NSStringFromSelector(@selector(stop:))],
                           @[@"退出", NSStringFromSelector(@selector(quit:))]]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:row[0] action:NSSelectorFromString(row[1]) keyEquivalent:@""];
        item.target = self;
        [menu addItem:item];
    }
    self.statusItem.menu = menu;
}
- (void)buildWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 680, 590)
         styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
         backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Yomado · Agent 虚拟屏";
    self.window.delegate = self;
    self.window.releasedWhenClosed = NO;
    [self.window center];
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.window.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:28],
        [stack.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-28],
        [stack.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:26]
    ]];
    [stack addArrangedSubview:Label(@"让 Agent 工作，让实体屏休息", 23, NSFontWeightSemibold)];
    [stack addArrangedSubview:Label(@"为 MD、Blender 等应用保留图形桌面。创建虚拟屏后，再测试实体屏能否进入待机。", 13, NSFontWeightRegular)];
    self.statusLabel = Label(@"尚未创建虚拟屏", 16, NSFontWeightSemibold);
    self.statusLabel.textColor = NSColor.systemBlueColor;
    [stack addArrangedSubview:self.statusLabel];
    self.inventoryLabel = Label(@"正在读取显示器…", 13, NSFontWeightRegular);
    [stack addArrangedSubview:self.inventoryLabel];
    NSStackView *resolutionRow = [[NSStackView alloc] init];
    resolutionRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    resolutionRow.spacing = 12;
    [resolutionRow addArrangedSubview:Label(@"虚拟桌面", 13, NSFontWeightMedium)];
    self.resolution = [[NSPopUpButton alloc] init];
    [self.resolution addItemsWithTitles:@[@"1920 × 1080", @"2560 × 1440"]];
    [resolutionRow addArrangedSubview:self.resolution];
    self.hiDPIBox = [NSButton checkboxWithTitle:@"HiDPI（更清晰）" target:nil action:NULL];
    [resolutionRow addArrangedSubview:self.hiDPIBox];
    [stack addArrangedSubview:resolutionRow];
    NSStackView *physicalRow = [[NSStackView alloc] init];
    physicalRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    physicalRow.spacing = 12;
    [physicalRow addArrangedSubview:Label(@"要关闭的实体屏", 13, NSFontWeightMedium)];
    self.physicalChoice = [[NSPopUpButton alloc] init];
    [self.physicalChoice.widthAnchor constraintGreaterThanOrEqualToConstant:230].active = YES;
    [physicalRow addArrangedSubview:self.physicalChoice];
    [stack addArrangedSubview:physicalRow];
    NSStackView *actions = [[NSStackView alloc] init];
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.spacing = 12;
    self.createButton = ADButton(@"1. 创建虚拟屏", self, @selector(create:));
    self.testButton = ADButton(@"实验：关屏测试 15 秒", self, @selector(startTrial:));
    [actions addArrangedSubview:self.createButton];
    [actions addArrangedSubview:self.testButton];
    [stack addArrangedSubview:actions];
    NSStackView *recovery = [[NSStackView alloc] init];
    recovery.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    recovery.spacing = 12;
    self.keepButton = ADButton(@"确认可操作，保持关屏", self, @selector(keepOff:));
    self.keepButton.enabled = NO;
    self.restoreButton = ADButton(@"恢复实体屏", self, @selector(restore:));
    [recovery addArrangedSubview:self.keepButton];
    [recovery addArrangedSubview:self.restoreButton];
    [recovery addArrangedSubview:ADButton(@"停止虚拟屏", self, @selector(stop:))];
    [stack addArrangedSubview:recovery];
    self.detailLabel = Label(@"先通过远程查看虚拟屏，确认能截图和点击。\n关屏测试未确认会在 15 秒后恢复；恢复快捷键：⌃⌥⌘R。", 13, NSFontWeightRegular);
    [stack addArrangedSubview:self.detailLabel];
    NSTextField *footer = Label(@"关闭窗口后应用仍留在菜单栏。退出前会恢复实体屏。\n此工具保持桌面唤醒；系统的锁屏与登录设置由你管理。", 12, NSFontWeightRegular);
    footer.textColor = NSColor.secondaryLabelColor;
    [stack addArrangedSubview:footer];
    for (NSView *view in @[stack.arrangedSubviews[1], self.inventoryLabel, self.detailLabel, footer]) {
        [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
}
- (void)showWindow:(id)sender {
    (void)sender;
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}
- (BOOL)windowShouldClose:(NSWindow *)window { [window orderOut:nil]; return NO; }
- (void)updateInventory {
    NSArray *snapshot = DisplaySnapshot();
    NSMutableArray *lines = [NSMutableArray array];
    CGDirectDisplayID selected = [self.physicalChoice.selectedItem.representedObject unsignedIntValue];
    [self.physicalChoice removeAllItems];
    for (NSDictionary *item in snapshot) {
        CGDirectDisplayID ident = [item[@"displayID"] unsignedIntValue];
        NSString *name = item[@"name"] ?: [NSString stringWithFormat:@"显示器 %u", ident];
        [lines addObject:[NSString stringWithFormat:@"%@ · %@ × %@%@", name,
             item[@"logicalWidth"], item[@"logicalHeight"], [item[@"isMain"] boolValue] ? @" · 主屏" : @""]];
        if (ident != self.virtualDisplay.displayID && ![VDVirtualDisplay isVirtualDisplay:ident]) {
            [self.physicalChoice addItemWithTitle:name];
            self.physicalChoice.lastItem.representedObject = @(ident);
            if (ident == selected) [self.physicalChoice selectItem:self.physicalChoice.lastItem];
        }
    }
    // Disabled targets disappear from online lists; keep a restore identity.
    if (self.armed) {
        for (NSNumber *ident in self.targets) [lines addObject:[NSString stringWithFormat:@"实体屏 %@ · 已请求待机", ident]];
    }
    self.inventoryLabel.stringValue = [lines componentsJoinedByString:@"\n"];
    self.resolution.enabled = !self.virtualDisplay.isCreated;
    self.hiDPIBox.enabled = !self.virtualDisplay.isCreated;
    self.createButton.enabled = !self.virtualDisplay.isCreated && !self.preparing;
    self.testButton.enabled = self.virtualDisplay.isCreated && !self.armed && !self.preparing
        && !self.recoveryRequested && !self.layoutChangedForTrial && EnableAPI() && self.hotkey && self.physicalChoice.numberOfItems > 0;
    self.physicalChoice.enabled = !self.armed && !self.preparing;
    self.restoreButton.enabled = self.armed || self.preparing || self.layoutChangedForTrial;
}
- (void)powerAssertions:(BOOL)on {
    if (on) {
        if (self.systemAssertion == kIOPMNullAssertionID)
            IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep, kIOPMAssertionLevelOn,
                CFSTR("Yomado virtual desktop"), &_systemAssertion);
        if (self.displayAssertion == kIOPMNullAssertionID)
            IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep, kIOPMAssertionLevelOn,
                CFSTR("Yomado virtual desktop rendering"), &_displayAssertion);
    } else {
        if (self.systemAssertion != kIOPMNullAssertionID) IOPMAssertionRelease(self.systemAssertion);
        if (self.displayAssertion != kIOPMNullAssertionID) IOPMAssertionRelease(self.displayAssertion);
        self.systemAssertion = self.displayAssertion = kIOPMNullAssertionID;
    }
}
- (BOOL)setVirtualMain:(BOOL)virtualMain {
    CGDisplayConfigRef config = NULL;
    if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess || !config) return NO;
    CGDirectDisplayID vd = self.virtualDisplay.displayID;
    CGDirectDisplayID primary = virtualMain ? vd : self.originalMain;
    if (!virtualMain && (!primary || !ADDisplayActive(primary))) {
        for (NSDictionary *item in DisplaySnapshot()) {
            CGDirectDisplayID candidate = [item[@"displayID"] unsignedIntValue];
            if (ADDisplayActive(candidate) && ![VDVirtualDisplay isVirtualDisplay:candidate]) { primary = candidate; break; }
        }
    }
    if (!primary || !ADDisplayActive(primary)) { CGCancelDisplayConfiguration(config); return NO; }
    int32_t originalX = 0, originalY = 0;
    if (!virtualMain) {
        for (NSDictionary *item in self.originalLayout) {
            if ([item[@"displayID"] unsignedIntValue] == primary) {
                originalX = [item[@"x"] intValue];
                originalY = [item[@"y"] intValue];
                break;
            }
        }
    }
    int32_t x = (int32_t)CGDisplayBounds(primary).size.width;
    CGError err = CGConfigureDisplayOrigin(config, primary, 0, 0);
    for (NSDictionary *item in self.originalLayout) {
        CGDirectDisplayID ident = [item[@"displayID"] unsignedIntValue];
        if (ident == primary || (virtualMain && ident == vd) || !ADDisplayOnline(ident)) continue;
        int32_t px = virtualMain ? x : [item[@"x"] intValue] - originalX;
        int32_t py = virtualMain ? 0 : [item[@"y"] intValue] - originalY;
        if (err == kCGErrorSuccess) err = CGConfigureDisplayOrigin(config, ident, px, py);
        if (virtualMain) x += (int32_t)CGDisplayBounds(ident).size.width;
    }
    if (err != kCGErrorSuccess) { CGCancelDisplayConfiguration(config); return NO; }
    return CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly) == kCGErrorSuccess;
}
- (BOOL)placeNewVirtualAtRight {
    // Configure only the display we own. Never replay an earlier desktop layout.
    NSNumber *right = YMPhysicalRightEdge(DisplaySnapshot());
    if (!right || !ADDisplayActive(self.virtualDisplay.displayID)) return NO;
    CGDisplayConfigRef config = NULL;
    if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess || !config) return NO;
    CGError error = CGConfigureDisplayOrigin(config, self.virtualDisplay.displayID, right.intValue, 0);
    if (error != kCGErrorSuccess) { CGCancelDisplayConfiguration(config); return NO; }
    return CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly) == kCGErrorSuccess;
}
- (void)create:(id)sender {
    (void)sender;
    if (self.virtualDisplay.isCreated) return;
    NSUInteger width = self.resolution.indexOfSelectedItem == 0 ? 1920 : 2560;
    NSUInteger height = self.resolution.indexOfSelectedItem == 0 ? 1080 : 1440;
    NSError *error = nil;
    if (![self.virtualDisplay createWithWidth:width height:height hiDPI:self.hiDPIBox.state == NSControlStateValueOn
                     name:@"Agent 虚拟屏" error:&error]) {
        self.statusLabel.stringValue = @"虚拟屏创建失败";
        self.detailLabel.stringValue = error.localizedDescription;
        return;
    }
    [self powerAssertions:YES];
    if (self.systemAssertion == kIOPMNullAssertionID || self.displayAssertion == kIOPMNullAssertionID) {
        [self stop:nil];
        self.statusLabel.stringValue = @"保持唤醒请求失败，未启用关屏";
        return;
    }
    self.statusLabel.stringValue = @"虚拟屏已创建，实体屏仍开启";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self.virtualDisplay.isCreated && !self.armed && !self.preparing) {
            if (![self placeNewVirtualAtRight])
                self.detailLabel.stringValue = @"虚拟屏已创建；请在系统显示器设置中确认排列位置。";
            [self updateInventory];
        }
    });
    self.detailLabel.stringValue = @"只把 Agent 所需窗口移入虚拟屏，保留实体主屏及自己的其他窗口。关屏试验会改变主屏与排列。";
    [self updateInventory];
}
- (BOOL)writeStateEnding:(BOOL)end {
    if (!self.statePath.length) return NO;
    NSMutableArray *origins = [NSMutableArray array];
    for (NSDictionary *item in self.originalLayout) {
        [origins addObject:@{@"id":item[@"displayID"], @"x":item[@"x"], @"y":item[@"y"]}];
    }
    NSDictionary *state = @{@"parentPID":@(getpid()), @"heartbeat":@(NSDate.date.timeIntervalSince1970 - (self.recoveryRequested ? 20 : 0)),
        @"armed":@(self.armed || self.layoutChangedForTrial), @"targets":self.targets ?: @[], @"virtualID":@(self.virtualDisplay.displayID),
        @"originalMain":@(self.originalMain), @"origins":origins, @"end":@(end)};
    NSData *data = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
    return [data writeToFile:self.statePath options:NSDataWritingAtomic error:nil];
}
- (void)finishWatchdog {
    [self writeStateEnding:YES];
    if (self.watchdog.running) [self.watchdog terminate];
    self.watchdog = nil;
    for (NSString *suffix in @[@"", @".ready", @".restored", @".error"])
        [NSFileManager.defaultManager removeItemAtPath:[self.statePath stringByAppendingString:suffix] error:nil];
}
- (BOOL)ensureWatchdog {
    if (self.watchdog.running) return NO;
    [self finishWatchdog];
    self.statePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"Yomado-%@.json", NSUUID.UUID.UUIDString]];
    if (![self writeStateEnding:NO]) return NO;
    NSString *exe = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/MacOS/YomadoWatchdog"];
    if (![NSFileManager.defaultManager isExecutableFileAtPath:exe]) return NO;
    self.watchdog = [[NSTask alloc] init];
    self.watchdog.executableURL = [NSURL fileURLWithPath:exe];
    self.watchdog.arguments = @[self.statePath, [NSString stringWithFormat:@"%d", getpid()]];
    self.watchdog.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    self.watchdog.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSError *error = nil;
    return [self.watchdog launchAndReturnError:&error];
}
- (void)startTrial:(id)sender {
    (void)sender;
    if (self.armed || self.preparing || self.restoring || self.recoveryRequested || self.layoutChangedForTrial
        || !self.virtualDisplay.isCreated || !ADDisplayActive(self.virtualDisplay.displayID)) return;
    CGDirectDisplayID target = [self.physicalChoice.selectedItem.representedObject unsignedIntValue];
    if (!target || target == self.virtualDisplay.displayID || [VDVirtualDisplay isVirtualDisplay:target]) return;
    if (CGDisplayIsInMirrorSet(target)) {
        self.detailLabel.stringValue = @"请先解除该实体显示器的镜像，再进行关屏测试。";
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"开始实验性 15 秒关屏测试？";
    alert.informativeText = @"试验会将虚拟屏设为主屏、改变显示排列，再关闭所选实体输出。macOS 或应用可能移动其他窗口，恢复不能保证窗口原位。请先保存工作，并确保能直接接触 Mac 和显示器。不确认将尝试自动恢复；恢复快捷键：⌃⌥⌘R。";
    [alert addButtonWithTitle:@"开始测试"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    // Recovery belongs to this explicit trial, never to display creation time.
    self.originalLayout = DisplaySnapshot();
    self.originalMain = CGMainDisplayID();
    self.targets = @[@(target)];
    self.preparing = YES;
    self.recoveryRequested = NO;
    NSUInteger generation = ++self.operationGeneration;
    self.statusLabel.stringValue = @"准备虚拟桌面与自动恢复…";
    if (![self ensureWatchdog]) {
        [self restore:nil];
        self.statusLabel.stringValue = @"没有关闭实体屏";
        self.detailLabel.stringValue = @"恢复进程或虚拟主屏准备失败，请重试。";
        [self updateInventory];
        return;
    }
    // Retain the snapshot even if completion fails: an attempted configuration
    // must be recovered before removal or another trial is allowed.
    self.layoutChangedForTrial = YES;
    if (![self writeStateEnding:NO] || ![self setVirtualMain:YES]) {
        [self restore:nil];
        return;
    }
    [self updateInventory];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (!self.preparing || generation != self.operationGeneration) return;
        NSString *ready = [self.statePath stringByAppendingString:@".ready"];
        if (!self.watchdog.running || ![NSFileManager.defaultManager fileExistsAtPath:ready]
            || !ADDisplayActive(self.virtualDisplay.displayID)
            || CGMainDisplayID() != self.virtualDisplay.displayID) {
            [self restore:nil];
            self.detailLabel.stringValue = @"虚拟主屏或独立恢复进程未就绪，实体屏保持开启。";
            return;
        }
        NSScreen *virtualScreen = nil;
        for (NSScreen *screen in NSScreen.screens)
            if ([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == self.virtualDisplay.displayID) virtualScreen = screen;
        if (virtualScreen) {
            NSRect frame = virtualScreen.visibleFrame;
            [self.window setFrameOrigin:NSMakePoint(frame.origin.x + 40, frame.origin.y + MAX(30, frame.size.height - 660))];
        }
        self.armed = YES;
        self.trialDeadline = NSDate.date.timeIntervalSince1970 + 15;
        if (![self writeStateEnding:NO]) { [self restore:nil]; return; }
        NSString *failure = nil;
        if (!ConfigureEnabled(self.targets, NO, &failure)) {
            [self restore:nil];
            self.detailLabel.stringValue = failure ?: @"实体屏关闭失败，已请求恢复。";
            return;
        }
        self.preparing = NO;
        self.keepButton.enabled = YES;
        self.detailLabel.stringValue = @"在虚拟桌面确认截图和点击正常后，点击「确认可操作，保持关屏」。未确认会自动恢复。";
        [self updateInventory];
    });
}
- (void)keepOff:(id)sender {
    (void)sender;
    if (!self.armed || self.trialDeadline <= 0 || !ADDisplayActive(self.virtualDisplay.displayID)) return;
    for (NSNumber *ident in self.targets) {
        if (ADDisplayActive(ident.unsignedIntValue)) {
            self.detailLabel.stringValue = @"实体屏仍处于活动状态，无法确认关屏成功。";
            return;
        }
    }
    self.trialDeadline = 0;
    self.keepButton.enabled = NO;
    self.statusLabel.stringValue = @"虚拟桌面运行中 · 实体屏已断开输出";
    self.detailLabel.stringValue = @"请确认实体屏确实不发光。输出已断开，但软件无法测量显示器的实际功耗。\n恢复：⌃⌥⌘R，或菜单栏「恢复实体显示器」。";
    [self writeStateEnding:NO];
}
- (void)restore:(id)sender {
    (void)sender;
    if (self.restoring) return;
    self.restoring = YES;
    ++self.operationGeneration;
    self.recoveryRequested = self.armed || self.layoutChangedForTrial;
    [self writeStateEnding:NO];
    self.preparing = NO;
    self.keepButton.enabled = NO;
    self.trialDeadline = 0;
    NSString *failure = nil;
    if (self.armed && !ConfigureEnabled(self.targets, YES, &failure)) {
        self.statusLabel.stringValue = @"实体屏恢复失败，虚拟屏继续保留";
        self.detailLabel.stringValue = failure ?: @"每秒重试恢复；独立恢复进程也已收到恢复信号。";
        self.restoring = NO;
        return;
    }
    if (self.armed) {
        BOOL allActive = YES;
        for (NSNumber *ident in self.targets) allActive &= ADDisplayActive(ident.unsignedIntValue) != 0;
        if (!allActive) {
            // Reconfiguration is asynchronous. Do not release the last usable desktop.
            self.statusLabel.stringValue = @"等待实体屏恢复…";
            self.restoring = NO;
            return;
        }
    }
    if (self.layoutChangedForTrial && ![self setVirtualMain:NO]) {
        self.statusLabel.stringValue = @"显示排列恢复失败，虚拟屏继续保留";
        self.detailLabel.stringValue = @"将继续尝试恢复本次试验前的排列。请检查实体屏连接。";
        self.restoring = NO;
        return;
    }
    self.layoutChangedForTrial = NO;
    self.armed = NO;
    self.recoveryRequested = NO;
    [self finishWatchdog];
    [self writeStateEnding:NO];
    self.statusLabel.stringValue = self.virtualDisplay.isCreated ? @"实体屏已恢复，虚拟屏仍保留" : @"尚未创建虚拟屏";
    self.detailLabel.stringValue = @"可继续使用虚拟屏，或从菜单栏停止并移除它。";
    self.restoring = NO;
    [self updateInventory];
    [self showWindow:nil];
}
- (void)tick:(NSTimer *)timer {
    (void)timer;
    if (![self writeStateEnding:NO] && self.armed) { [self restore:nil]; return; }
    NSString *restoredPath = [self.statePath stringByAppendingString:@".restored"];
    if ([NSFileManager.defaultManager fileExistsAtPath:restoredPath]) {
        [NSFileManager.defaultManager removeItemAtPath:restoredPath error:nil];
        [self restore:nil];
        self.detailLabel.stringValue = @"独立恢复进程已恢复实体屏。重新测试前请确认虚拟屏可用。";
    }
    if (self.recoveryRequested || (self.armed && (!self.watchdog.running || !ADDisplayActive(self.virtualDisplay.displayID)))) { [self restore:nil]; return; }
    if (self.armed && self.trialDeadline > 0) {
        NSInteger remaining = (NSInteger)ceil(self.trialDeadline - NSDate.date.timeIntervalSince1970);
        if (remaining <= 0) { [self restore:nil]; return; }
        self.statusLabel.stringValue = [NSString stringWithFormat:@"实体屏关屏测试 · %ld 秒后自动恢复", (long)remaining];
    }
}
- (void)systemWillSleep:(NSNotification *)notification { (void)notification; [self restore:nil]; }
- (void)stop:(id)sender {
    (void)sender;
    if (self.armed || self.preparing || self.layoutChangedForTrial) [self restore:nil];
    if (self.armed || self.preparing || self.restoring || self.layoutChangedForTrial) return;
    if (self.virtualDisplay.isCreated) {
        BOOL physicalActive = NO;
        for (NSDictionary *item in DisplaySnapshot()) {
            CGDirectDisplayID ident = [item[@"displayID"] unsignedIntValue];
            if (ADDisplayActive(ident) && ![VDVirtualDisplay isVirtualDisplay:ident]) physicalActive = YES;
        }
        BOOL mainReady = physicalActive;
        if (mainReady && CGMainDisplayID() == self.virtualDisplay.displayID) {
            // A manual main-display change needs a physical fallback. Rebase
            // the current arrangement, not an old creation or trial snapshot.
            self.originalLayout = DisplaySnapshot();
            self.originalMain = 0;
            mainReady = [self setVirtualMain:NO];
        }
        if (!mainReady) {
            self.statusLabel.stringValue = @"保留虚拟屏：尚无可用的实体主屏";
            self.detailLabel.stringValue = @"请先打开或重新连接实体显示器，再停止或退出。";
            return;
        }
    }
    [self finishWatchdog];
    [self.virtualDisplay destroy];
    [self powerAssertions:NO];
    self.statusLabel.stringValue = @"虚拟屏已移除，实体屏正常运行";
    self.detailLabel.stringValue = @"再次点击「创建虚拟屏」即可重新使用。";
    [self updateInventory];
}
- (void)quit:(id)sender { (void)sender; [NSApp terminate:nil]; }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
    [self stop:nil];
    if (self.armed || self.preparing || self.restoring || self.layoutChangedForTrial || self.virtualDisplay.isCreated) {
        [self showWindow:nil];
        return NSTerminateCancel;
    }
    [self writeStateEnding:YES];
    return NSTerminateNow;
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self.heartbeatTimer invalidate];
    if (self.hotkey) UnregisterEventHotKey(self.hotkey);
    if (self.keyHandler) RemoveEventHandler(self.keyHandler);
    [self powerAssertions:NO];
}
@end

static int SelfTest(NSString *directory, BOOL hiDPI) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [NSApp finishLaunching];
    NSArray *before = DisplaySnapshot();
    CGDirectDisplayID originalMain = CGMainDisplayID();
    VDVirtualDisplay *display = [[VDVirtualDisplay alloc] initWithSerialNumber:hiDPI ? 0x41445402 : 0x41445401];
    NSError *error = nil;
    if (![display createWithWidth:1920 height:1080 hiDPI:hiDPI name:@"Yomado Test" error:&error]) {
        fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return 1;
    }
    CGDirectDisplayID ident = display.displayID;
    BOOL active = WaitUntil(^BOOL{ return ADDisplayActive(ident) != 0; }, 5);
    CGRect bounds = CGDisplayBounds(ident);
    __block NSScreen *virtualScreen = nil;
    BOOL screenFound = WaitUntil(^BOOL{
        for (NSScreen *screen in NSScreen.screens)
            if ([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == ident) virtualScreen = screen;
        return virtualScreen != nil;
    }, 5);
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(ident);
    size_t pixelsWide = mode ? CGDisplayModeGetPixelWidth(mode) : 0;
    size_t pixelsHigh = mode ? CGDisplayModeGetPixelHeight(mode) : 0;
    if (mode) CGDisplayModeRelease(mode);
    CGFloat scale = virtualScreen.backingScaleFactor;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 240)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.title = @"Yomado 验证窗口";
    ADTestView *view = [[ADTestView alloc] initWithFrame:NSMakeRect(0, 0, 500, 240)];
    window.contentView = view;
    if (virtualScreen) [window setFrameOrigin:NSMakePoint(virtualScreen.frame.origin.x + 50, virtualScreen.frame.origin.y + 50)];
    [window orderFront:nil];
    BOOL windowOnVirtual = WaitUntil(^BOOL{ return [window.screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == ident; }, 3);
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    NSData *first = [view PNGData];
    view.frameNumber = 1;
    view.needsDisplay = YES;
    NSData *second = [view PNGData];
    BOOL directoryWritten = [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    BOOL firstWritten = [first writeToFile:[directory stringByAppendingPathComponent:@"frame-0.png"] atomically:YES];
    BOOL secondWritten = [second writeToFile:[directory stringByAppendingPathComponent:@"frame-1.png"] atomically:YES];
    // Exercise exactly the enable/disable API, but ONLY on our temporary virtual display.
    NSString *failure = nil;
    BOOL disabled = ConfigureEnabled(@[@(ident)], NO, &failure)
        && WaitUntil(^BOOL{ return ADDisplayActive(ident) == 0; }, 4);
    BOOL reenabled = ConfigureEnabled(@[@(ident)], YES, &failure)
        && WaitUntil(^BOOL{ return ADDisplayActive(ident) != 0; }, 4);
    NSArray *during = DisplaySnapshot();
    [window orderOut:nil];
    [window close];
    [display destroy];
    BOOL removed = WaitUntil(^BOOL{ return ADDisplayOnline(ident) == 0; }, 5);
    CGDisplayConfigRef layout = NULL;
    BOOL layoutRestored = CGBeginDisplayConfiguration(&layout) == kCGErrorSuccess;
    if (layoutRestored) {
        for (NSDictionary *item in before) {
            CGError err = CGConfigureDisplayOrigin(layout, [item[@"displayID"] unsignedIntValue], [item[@"x"] intValue], [item[@"y"] intValue]);
            if (err != kCGErrorSuccess) layoutRestored = NO;
        }
        if (layoutRestored) layoutRestored = CGCompleteDisplayConfiguration(layout, kCGConfigureForAppOnly) == kCGErrorSuccess;
        else CGCancelDisplayConfiguration(layout);
    }
    BOOL settled = WaitUntil(^BOOL{
        for (NSDictionary *item in before) {
            CGRect expected = CGRectMake([item[@"x"] doubleValue], [item[@"y"] doubleValue], [item[@"logicalWidth"] doubleValue], [item[@"logicalHeight"] doubleValue]);
            if (!CGRectEqualToRect(expected, CGDisplayBounds([item[@"displayID"] unsignedIntValue]))) return NO;
        }
        return YES;
    }, 3);
    NSArray *after = DisplaySnapshot();
    BOOL physicalTopologyRestored = layoutRestored && settled && before.count == after.count;
    for (NSDictionary *item in before) {
        CGDirectDisplayID prior = [item[@"displayID"] unsignedIntValue];
        CGRect expected = CGRectMake([item[@"x"] doubleValue], [item[@"y"] doubleValue], [item[@"logicalWidth"] doubleValue], [item[@"logicalHeight"] doubleValue]);
        physicalTopologyRestored &= ADDisplayActive(prior) && CGRectEqualToRect(expected, CGDisplayBounds(prior));
    }
    BOOL pass = active && screenFound && windowOnVirtual && physicalTopologyRestored
        && bounds.size.width == 1920 && bounds.size.height == 1080
        && pixelsWide == 1920 * (hiDPI ? 2 : 1) && pixelsHigh == 1080 * (hiDPI ? 2 : 1)
        && scale == (hiDPI ? 2 : 1) && directoryWritten && firstWritten && secondWritten
        && first.length > 0 && second.length > 0 && ![first isEqualToData:second]
        && disabled && reenabled && removed && CGMainDisplayID() == originalMain && before.count == after.count;
    NSDictionary *receipt = @{@"pass":@(pass), @"hiDPI":@(hiDPI), @"virtualID":@(ident),
        @"virtualActive":@(active), @"screenFound":@(screenFound), @"windowOnVirtual":@(windowOnVirtual),
        @"physicalTopologyRestored":@(physicalTopologyRestored), @"pixelWidth":@(pixelsWide), @"pixelHeight":@(pixelsHigh),
        @"backingScale":@(scale), @"framesExported":@(directoryWritten && firstWritten && secondWritten), @"logicalWidth":@(bounds.size.width), @"logicalHeight":@(bounds.size.height),
        @"ownViewFramesDiffer":@(![first isEqualToData:second]), @"virtualDisableVerified":@(disabled),
        @"virtualEnableVerified":@(reenabled), @"virtualRemoved":@(removed),
        @"physicalDisplaysNeverDisabled":@YES, @"mainDisplayRestored":@(CGMainDisplayID() == originalMain),
        @"before":before, @"during":during, @"after":after,
        @"scope":@"Own AppKit view only; not screen capture of MD/Blender; no monitor power measurement.",
        @"error":failure ?: @""};
    NSString *json = JSONText(receipt);
    BOOL receiptWritten = [json writeToFile:[directory stringByAppendingPathComponent:@"receipt.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    printf("%s\n", json.UTF8String);
    return pass && receiptWritten ? 0 : 2;
}

// Exercise independent recovery against only an owned temporary virtual display.
// The existing main physical display stays active throughout this check.
static int WatchdogTest(NSString *directory, NSString *helperPath) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [NSApp finishLaunching];
    CGDirectDisplayID originalMain = CGMainDisplayID();
    NSArray *before = DisplaySnapshot();
    VDVirtualDisplay *display = [[VDVirtualDisplay alloc] initWithSerialNumber:0x41445701];
    NSError *error = nil;
    if (![display createWithWidth:1280 height:720 hiDPI:NO name:@"Yomado Recovery Test" error:&error]) return 1;
    CGDirectDisplayID target = display.displayID;
    BOOL created = WaitUntil(^BOOL{ return ADDisplayActive(target); }, 5);
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"watchdog-%@.json", NSUUID.UUID.UUIDString]];
    NSTask *fakeParent = [[NSTask alloc] init];
    fakeParent.executableURL = [NSURL fileURLWithPath:@"/bin/sleep"];
    fakeParent.arguments = @[@"30"];
    BOOL parentLaunched = [fakeParent launchAndReturnError:&error];
    NSDictionary *state = @{@"parentPID":@(fakeParent.processIdentifier), @"heartbeat":@(NSDate.date.timeIntervalSince1970),
        @"armed":@YES, @"end":@NO, @"targets":@[@(target)], @"virtualID":@(originalMain)};
    BOOL stateWritten = [[NSJSONSerialization dataWithJSONObject:state options:0 error:nil] writeToFile:path atomically:YES];
    NSTask *helper = [[NSTask alloc] init];
    helper.executableURL = [NSURL fileURLWithPath:helperPath];
    helper.arguments = @[path, [NSString stringWithFormat:@"%d", fakeParent.processIdentifier]];
    helper.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    helper.standardError = NSFileHandle.fileHandleWithNullDevice;
    BOOL helperLaunched = parentLaunched && stateWritten && [helper launchAndReturnError:&error];
    BOOL ready = helperLaunched && WaitUntil(^BOOL{ return [NSFileManager.defaultManager fileExistsAtPath:[path stringByAppendingString:@".ready"]]; }, 4);
    BOOL disabled = ready && ConfigureEnabled(@[@(target)], NO, nil)
        && WaitUntil(^BOOL{ return !ADDisplayActive(target); }, 4);
    if (fakeParent.running) [fakeParent terminate];
    BOOL restored = disabled && WaitUntil(^BOOL{
        return [NSFileManager.defaultManager fileExistsAtPath:[path stringByAppendingString:@".restored"]] && ADDisplayActive(target);
    }, 8);
    BOOL helperExited = helperLaunched && WaitUntil(^BOOL{ return !helper.running; }, 2);
    if (helper.running) [helper terminate];
    if (fakeParent.running) [fakeParent terminate];
    if (!ADDisplayActive(target)) ConfigureEnabled(@[@(target)], YES, nil);
    [display destroy];
    BOOL removed = WaitUntil(^BOOL{ return !ADDisplayOnline(target); }, 5);
    CGDisplayConfigRef layout = NULL;
    BOOL layoutRestored = CGBeginDisplayConfiguration(&layout) == kCGErrorSuccess;
    if (layoutRestored) {
        for (NSDictionary *item in before) {
            CGError err = CGConfigureDisplayOrigin(layout, [item[@"displayID"] unsignedIntValue], [item[@"x"] intValue], [item[@"y"] intValue]);
            if (err != kCGErrorSuccess) layoutRestored = NO;
        }
        if (layoutRestored) layoutRestored = CGCompleteDisplayConfiguration(layout, kCGConfigureForAppOnly) == kCGErrorSuccess;
        else CGCancelDisplayConfiguration(layout);
    }
    WaitUntil(^BOOL{
        for (NSDictionary *item in before) {
            CGRect expected = CGRectMake([item[@"x"] doubleValue], [item[@"y"] doubleValue], [item[@"logicalWidth"] doubleValue], [item[@"logicalHeight"] doubleValue]);
            if (!CGRectEqualToRect(expected, CGDisplayBounds([item[@"displayID"] unsignedIntValue]))) return NO;
        }
        return YES;
    }, 3);
    BOOL physicalRestored = layoutRestored && CGMainDisplayID() == originalMain;
    for (NSDictionary *item in before) {
        CGDirectDisplayID ident = [item[@"displayID"] unsignedIntValue];
        CGRect expected = CGRectMake([item[@"x"] doubleValue], [item[@"y"] doubleValue], [item[@"logicalWidth"] doubleValue], [item[@"logicalHeight"] doubleValue]);
        physicalRestored &= ADDisplayActive(ident) && CGRectEqualToRect(expected, CGDisplayBounds(ident));
    }
    BOOL pass = created && ready && disabled && restored && helperExited && removed && physicalRestored;
    NSDictionary *receipt = @{@"pass":@(pass), @"helperReady":@(ready), @"ownedVirtualDisabled":@(disabled),
        @"parentExitRecovery":@(restored), @"helperExited":@(helperExited), @"virtualRemoved":@(removed),
        @"physicalTopologyRestored":@(physicalRestored), @"physicalDisplaysNeverDisabled":@YES,
        @"scope":@"Killed a disposable child process; recovery target was only an owned temporary virtual display."};
    NSString *json = JSONText(receipt);
    BOOL written = [json writeToFile:[directory stringByAppendingPathComponent:@"receipt.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    printf("%s\n", json.UTF8String);
    for (NSString *suffix in @[@"", @".ready", @".restored", @".error"])
        [NSFileManager.defaultManager removeItemAtPath:[path stringByAppendingString:suffix] error:nil];
    return pass && written ? 0 : 2;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--diagnose") == 0) {
            BOOL includeIdentifiers = argc == 3 && strcmp(argv[2], "--include-device-identifiers") == 0;
            if (argc > 2 && !includeIdentifiers) {
                fprintf(stderr, "Usage: Yomado --diagnose [--include-device-identifiers]\n");
                return 64;
            }
            printf("%s\n", JSONTextWithIdentifiers(@{@"virtualDisplayAPI":@([VDVirtualDisplay isAPIAvailable]),
                @"physicalDisplaySwitchAPI":@(EnableAPI() != NULL), @"displays":DisplaySnapshot()}, includeIdentifiers).UTF8String);
            return 0;
        }
        if (argc > 2 && strcmp(argv[1], "--self-test") == 0)
            return SelfTest([NSString stringWithUTF8String:argv[2]], argc > 3 && strcmp(argv[3], "hidpi") == 0);
        if (argc > 3 && strcmp(argv[1], "--watchdog-test") == 0)
            return WatchdogTest([NSString stringWithUTF8String:argv[2]], [NSString stringWithUTF8String:argv[3]]);
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        ADController *controller = [[ADController alloc] init];
        NSApp.delegate = controller;
        [NSApp run];
        return 0;
    }
}
