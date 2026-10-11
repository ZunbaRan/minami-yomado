#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <Carbon/Carbon.h>
#import <dlfcn.h>
#import <signal.h>
#import "VDVirtualDisplay.h"
#import "LayoutPolicy.h"
#import "DiagnosticPrivacy.h"
#import "ControlUI.h"
#import "WindowRecovery.h"

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
@property YMTopologyView *topologyView;
@property YMStatusPill *statusPill;
@property NSTextField *sessionHeadline;
@property NSTextField *sessionCaption;
@property NSTextField *sessionResolution;
@property NSTextField *wakeLabel;
@property NSTextField *placementLabel;
@property NSButton *experimentToggle;
@property NSView *experimentContent;
@property NSTextField *wechatStatusLabel;
@property NSTextField *wechatPermissionGuide;
@property(copy) NSString *wechatPermissionMessage;
@property NSButton *wechatMoveButton;
@property NSButton *wechatRestoreButton;
@property NSButton *wechatPermissionButton;
@property YMWindowRecovery *windowRecovery;
@property BOOL experimentsExpanded;
@property BOOL previewMode;
@property(copy) NSString *previewState;
@property(copy) NSArray<NSDictionary *> *previewSnapshot;
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
- (void)buildWindow;
- (void)updateInventory;
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
static NSStackView *YMStack(NSUserInterfaceLayoutOrientation orientation, CGFloat spacing) {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = orientation;
    stack.alignment = orientation == NSUserInterfaceLayoutOrientationVertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    stack.spacing = spacing;
    stack.distribution = NSStackViewDistributionFill;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.detachesHiddenViews = YES;
    return stack;
}
static void YMFillWidth(NSView *child, NSView *parent) {
    [child.widthAnchor constraintEqualToAnchor:parent.widthAnchor].active = YES;
}
static NSView *YMSpacer(void) {
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    return spacer;
}
static NSView *YMCard(NSStackView **content) {
    YMPanelView *card = [[YMPanelView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    NSStackView *stack = YMStack(NSUserInterfaceLayoutOrientationVertical, 12);
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18]
    ]];
    *content = stack;
    return card;
}
static NSStackView *YMValueRow(NSString *title, NSTextField **value) {
    NSStackView *row = YMStack(NSUserInterfaceLayoutOrientationHorizontal, 10);
    NSTextField *label = Label(title, 12, NSFontWeightRegular);
    label.textColor = NSColor.secondaryLabelColor;
    [row addArrangedSubview:label];
    [row addArrangedSubview:YMSpacer()];
    NSTextField *field = Label(@"—", 12, NSFontWeightMedium);
    field.alignment = NSTextAlignmentRight;
    [row addArrangedSubview:field];
    *value = field;
    return row;
}
@interface YMDocumentView : NSView
@end
@implementation YMDocumentView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor.windowBackgroundColor blendedColorWithFraction:0.035 ofColor:NSColor.labelColor] setFill];
    NSRectFill(self.bounds);
}
@end

@implementation ADController
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if (self.previewMode) return;
    (void)notification;
    self.virtualDisplay = [[VDVirtualDisplay alloc] initWithSerialNumber:0x41443101];
    self.windowRecovery = [[YMWindowRecovery alloc] initWithCheckpointURL:nil];
    self.targets = @[];
    self.systemAssertion = kIOPMNullAssertionID;
    self.displayAssertion = kIOPMNullAssertionID;
    self.statePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"Yomado-%@.json", NSUUID.UUID.UUIDString]];
    [self buildMenu];
    NSMenu *main = [[NSMenu alloc] init];
    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"yomado" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"yomado"];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"退出 yomado" action:@selector(quit:) keyEquivalent:@"q"];
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
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(displayParametersChanged:)
          name:NSApplicationDidChangeScreenParametersNotification object:nil];
}
- (void)buildMenu {
    if (self.previewMode) return;
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"display.2" accessibilityDescription:@"Agent 虚拟屏"];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"yomado"];
    for (NSArray *row in @[@[@"打开控制面板", NSStringFromSelector(@selector(showWindow:))],
                           @[@"微信返回原显示器", NSStringFromSelector(@selector(wechatRestore:))],
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
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 920, 820)
         styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
         backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"yomado";
    self.window.titlebarAppearsTransparent = YES;
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.contentMinSize = NSMakeSize(860, 680);
    self.window.delegate = self.previewMode ? nil : self;
    self.window.releasedWhenClosed = NO;
    if (!self.previewMode) [self.window center];

    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.drawsBackground = YES;
    scroll.backgroundColor = NSColor.windowBackgroundColor;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    [self.window.contentView addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.window.contentView.bottomAnchor]
    ]];
    YMDocumentView *document = [[YMDocumentView alloc] initWithFrame:NSMakeRect(0, 0, 920, 760)];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.documentView = document;
    NSStackView *stack = YMStack(NSUserInterfaceLayoutOrientationVertical, 18);
    [document addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [document.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [document.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [document.heightAnchor constraintGreaterThanOrEqualToAnchor:scroll.contentView.heightAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:28],
        [stack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-28],
        [stack.topAnchor constraintEqualToAnchor:document.topAnchor constant:18],
        [stack.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-22]
    ]];

    NSStackView *header = YMStack(NSUserInterfaceLayoutOrientationHorizontal, 14);
    NSURL *iconURL = [NSBundle.mainBundle URLForResource:@"Yomado" withExtension:@"icns"];
    NSImage *appIcon = iconURL ? [[NSImage alloc] initWithContentsOfURL:iconURL] : nil;
    if (appIcon) {
        NSImageView *iconView = [NSImageView imageViewWithImage:appIcon];
        iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
        [iconView.widthAnchor constraintEqualToConstant:60].active = YES;
        [iconView.heightAnchor constraintEqualToConstant:60].active = YES;
        [iconView setAccessibilityLabel:@"yomado 夜窗图标"];
        [header addArrangedSubview:iconView];
        if (!self.previewMode) NSApp.applicationIconImage = appIcon;
    }
    NSStackView *brand = YMStack(NSUserInterfaceLayoutOrientationVertical, 4);
    [brand addArrangedSubview:Label(@"yomado", 30, NSFontWeightSemibold)];
    NSTextField *subtitle = Label(@"为视觉 Agent 留一块工作屏", 13, NSFontWeightRegular);
    subtitle.textColor = NSColor.secondaryLabelColor;
    [brand addArrangedSubview:subtitle];
    [header addArrangedSubview:brand];
    [header addArrangedSubview:YMSpacer()];
    self.statusPill = [[YMStatusPill alloc] init];
    [header addArrangedSubview:self.statusPill];
    [stack addArrangedSubview:header]; YMFillWidth(header, stack);

    NSStackView *workspaceContent;
    NSView *workspace = YMCard(&workspaceContent);
    NSStackView *workspaceRow = YMStack(NSUserInterfaceLayoutOrientationHorizontal, 20);
    workspaceRow.alignment = NSLayoutAttributeTop;
    NSStackView *layout = YMStack(NSUserInterfaceLayoutOrientationVertical, 7);
    [layout setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [layout addArrangedSubview:Label(@"桌面排列", 14, NSFontWeightSemibold)];
    self.inventoryLabel = Label(@"正在读取显示器…", 11, NSFontWeightRegular);
    self.inventoryLabel.textColor = NSColor.secondaryLabelColor;
    [layout addArrangedSubview:self.inventoryLabel]; YMFillWidth(self.inventoryLabel, layout);
    self.topologyView = [[YMTopologyView alloc] init];
    self.topologyView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topologyView.heightAnchor constraintEqualToConstant:190].active = YES;
    [layout addArrangedSubview:self.topologyView]; YMFillWidth(self.topologyView, layout);
    self.placementLabel = Label(@"新虚拟屏默认放在实体屏右侧，实体主屏保持原位。", 12, NSFontWeightRegular);
    self.placementLabel.textColor = NSColor.secondaryLabelColor;
    [layout addArrangedSubview:self.placementLabel]; YMFillWidth(self.placementLabel, layout);
    [workspaceRow addArrangedSubview:layout];
    NSBox *divider = [[NSBox alloc] init];
    divider.boxType = NSBoxSeparator;
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    [divider.widthAnchor constraintEqualToConstant:1].active = YES;
    [divider.heightAnchor constraintEqualToConstant:260].active = YES;
    [workspaceRow addArrangedSubview:divider];
    NSStackView *session = YMStack(NSUserInterfaceLayoutOrientationVertical, 12);
    [session.widthAnchor constraintEqualToConstant:246].active = YES;
    [session addArrangedSubview:Label(@"Agent 工作屏", 14, NSFontWeightSemibold)];
    self.sessionHeadline = Label(@"从一块虚拟屏开始", 21, NSFontWeightSemibold);
    [session addArrangedSubview:self.sessionHeadline]; YMFillWidth(self.sessionHeadline, session);
    self.sessionCaption = Label(@"给截图与键鼠操作保留桌面，实体屏继续供你使用。", 12, NSFontWeightRegular);
    self.sessionCaption.textColor = NSColor.secondaryLabelColor;
    [session addArrangedSubview:self.sessionCaption]; YMFillWidth(self.sessionCaption, session);
    NSTextField *resolutionValue;
    NSStackView *resolutionValueRow = YMValueRow(@"桌面尺寸", &resolutionValue);
    self.sessionResolution = resolutionValue;
    [session addArrangedSubview:resolutionValueRow]; YMFillWidth(resolutionValueRow, session);
    NSTextField *wakeValue;
    NSStackView *wakeRow = YMValueRow(@"保持唤醒", &wakeValue);
    self.wakeLabel = wakeValue;
    [session addArrangedSubview:wakeRow]; YMFillWidth(wakeRow, session);
    self.createButton = ADButton(@"创建虚拟屏", self, @selector(primaryAction:));
    self.createButton.bezelColor = NSColor.controlAccentColor;
    self.createButton.controlSize = NSControlSizeLarge;
    [self.createButton.heightAnchor constraintEqualToConstant:34].active = YES;
    [session addArrangedSubview:self.createButton]; YMFillWidth(self.createButton, session);
    [workspaceRow addArrangedSubview:session];
    [workspaceContent addArrangedSubview:workspaceRow]; YMFillWidth(workspaceRow, workspaceContent);
    [stack addArrangedSubview:workspace]; YMFillWidth(workspace, stack);

    NSStackView *settingsContent;
    NSView *settings = YMCard(&settingsContent);
    NSStackView *settingsRow = YMStack(NSUserInterfaceLayoutOrientationHorizontal, 14);
    [settingsRow addArrangedSubview:Label(@"虚拟桌面", 14, NSFontWeightSemibold)];
    [settingsRow addArrangedSubview:YMSpacer()];
    NSTextField *resolutionLabel = Label(@"分辨率", 12, NSFontWeightRegular);
    resolutionLabel.textColor = NSColor.secondaryLabelColor;
    [settingsRow addArrangedSubview:resolutionLabel];
    self.resolution = [[NSPopUpButton alloc] init];
    [self.resolution addItemsWithTitles:@[@"1920 × 1080", @"2560 × 1440"]];
    self.resolution.target = self;
    self.resolution.action = @selector(presentationSettingsChanged:);
    [self.resolution setAccessibilityLabel:@"虚拟桌面分辨率"];
    [self.resolution.widthAnchor constraintEqualToConstant:170].active = YES;
    [settingsRow addArrangedSubview:self.resolution];
    self.hiDPIBox = [NSButton checkboxWithTitle:@"HiDPI 更清晰" target:self action:@selector(presentationSettingsChanged:)];
    [settingsRow addArrangedSubview:self.hiDPIBox];
    [settingsContent addArrangedSubview:settingsRow]; YMFillWidth(settingsRow, settingsContent);
    NSTextField *settingsNote = Label(@"运行时更改分辨率需先停止虚拟屏。排列位置可在系统显示器设置中调整。", 11, NSFontWeightRegular);
    settingsNote.textColor = NSColor.secondaryLabelColor;
    [settingsContent addArrangedSubview:settingsNote]; YMFillWidth(settingsNote, settingsContent);
    [stack addArrangedSubview:settings]; YMFillWidth(settings, stack);

    NSStackView *workflow = YMStack(NSUserInterfaceLayoutOrientationHorizontal, 12);
    NSArray *steps = @[@"① 创建虚拟屏", @"② 只移入 Agent 所需窗口", @"③ 让 Agent 截图与点击"];
    for (NSUInteger index = 0; index < steps.count; index++) {
        NSTextField *step = Label(steps[index], 12, NSFontWeightMedium);
        step.textColor = NSColor.secondaryLabelColor;
        [workflow addArrangedSubview:step];
        [step.widthAnchor constraintEqualToAnchor:workflow.widthAnchor multiplier:1.0 / 3.0 constant:-8].active = YES;
    }
    [stack addArrangedSubview:workflow]; YMFillWidth(workflow, stack);

    NSStackView *statusContent;
    NSView *status = YMCard(&statusContent);
    statusContent.spacing = 7;
    NSStackView *statusRow = YMStack(NSUserInterfaceLayoutOrientationHorizontal, 12);
    self.statusLabel = Label(@"尚未创建虚拟屏", 13, NSFontWeightSemibold);
    [statusRow addArrangedSubview:self.statusLabel];
    [statusRow addArrangedSubview:YMSpacer()];
    self.keepButton = ADButton(@"确认并保持输出关闭", self, @selector(keepOff:));
    self.keepButton.hidden = YES;
    self.keepButton.enabled = NO;
    [statusRow addArrangedSubview:self.keepButton];
    self.restoreButton = ADButton(@"恢复实体屏", self, @selector(restore:));
    self.restoreButton.hidden = YES;
    [statusRow addArrangedSubview:self.restoreButton];
    [statusContent addArrangedSubview:statusRow]; YMFillWidth(statusRow, statusContent);
    self.detailLabel = Label(@"yomado 不会自动搬动其他应用。只把 Agent 需要的窗口移入虚拟屏，你的其他界面留在实体屏。", 12, NSFontWeightRegular);
    self.detailLabel.textColor = NSColor.secondaryLabelColor;
    [statusContent addArrangedSubview:self.detailLabel]; YMFillWidth(self.detailLabel, statusContent);
    [stack addArrangedSubview:status]; YMFillWidth(status, stack);

    NSStackView *wechatContent;
    NSView *wechat = YMCard(&wechatContent);
    wechatContent.spacing = 8;
    NSStackView *wechatHeader = YMStack(NSUserInterfaceLayoutOrientationHorizontal, 12);
    [wechatHeader addArrangedSubview:Label(@"微信窗口", 14, NSFontWeightSemibold)];
    [wechatHeader addArrangedSubview:YMSpacer()];
    self.wechatPermissionButton = ADButton(@"打开控制权限设置…", self, @selector(wechatPermission:));
    self.wechatPermissionButton.enabled = NO;
    [wechatHeader addArrangedSubview:self.wechatPermissionButton];
    [wechatContent addArrangedSubview:wechatHeader]; YMFillWidth(wechatHeader, wechatContent);
    self.wechatStatusLabel = Label(@"尚未记录窗口位置。移入前先保留原实体屏位置，便于恢复。", 12, NSFontWeightRegular);
    self.wechatStatusLabel.textColor = NSColor.secondaryLabelColor;
    [wechatContent addArrangedSubview:self.wechatStatusLabel]; YMFillWidth(self.wechatStatusLabel, wechatContent);
    NSString *permissionPane = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
        ? @"设备控制和数据访问" : @"辅助功能";
    self.wechatPermissionGuide = Label([NSString stringWithFormat:@"① 点击右上方按钮，进入“隐私与安全 → %@”。\n② 在列表中开启 yomado；若未出现，点“＋”选择此应用。\n③ 回到这里，权限状态会自动更新，再开始移屏。", permissionPane], 12, NSFontWeightRegular);
    self.wechatPermissionGuide.textColor = NSColor.secondaryLabelColor;
    [wechatContent addArrangedSubview:self.wechatPermissionGuide]; YMFillWidth(self.wechatPermissionGuide, wechatContent);
    NSStackView *wechatActions = YMStack(NSUserInterfaceLayoutOrientationHorizontal, 12);
    self.wechatMoveButton = ADButton(@"记住位置并移入虚拟屏", self, @selector(wechatMove:));
    self.wechatMoveButton.enabled = NO;
    self.wechatRestoreButton = ADButton(@"返回原显示器", self, @selector(wechatRestore:));
    self.wechatRestoreButton.enabled = NO;
    [wechatActions addArrangedSubview:self.wechatMoveButton];
    [wechatActions addArrangedSubview:self.wechatRestoreButton];
    [wechatActions addArrangedSubview:YMSpacer()];
    NSTextField *wechatPrivacy = Label(@"仅记窗口位置，不保存聊天或登录信息", 11, NSFontWeightRegular);
    wechatPrivacy.textColor = NSColor.tertiaryLabelColor;
    [wechatActions addArrangedSubview:wechatPrivacy];
    [wechatContent addArrangedSubview:wechatActions]; YMFillWidth(wechatActions, wechatContent);
    NSTextField *wechatNote = Label(@"登录提示自动识别有限；手动返回入口始终保留，登录与验证由你本人完成。", 11, NSFontWeightRegular);
    wechatNote.textColor = NSColor.secondaryLabelColor;
    [wechatContent addArrangedSubview:wechatNote]; YMFillWidth(wechatNote, wechatContent);
    [stack addArrangedSubview:wechat]; YMFillWidth(wechat, stack);

    NSStackView *experiments = YMStack(NSUserInterfaceLayoutOrientationVertical, 10);
    self.experimentToggle = [NSButton buttonWithTitle:@"实验功能 · 实体屏输出测试" target:self action:@selector(toggleExperiments:)];
    self.experimentToggle.bordered = NO;
    self.experimentToggle.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    self.experimentToggle.contentTintColor = NSColor.secondaryLabelColor;
    self.experimentToggle.image = [NSImage imageWithSystemSymbolName:@"chevron.right" accessibilityDescription:nil];
    self.experimentToggle.imagePosition = NSImageLeft;
    [self.experimentToggle setAccessibilityLabel:@"展开实验性实体屏输出测试"];
    [experiments addArrangedSubview:self.experimentToggle];
    NSStackView *experimentContent;
    self.experimentContent = YMCard(&experimentContent);
    self.experimentContent.hidden = YES;
    NSTextField *warning = Label(@"会改变主屏与显示排列，macOS 可能移动其他窗口。请先保存工作，并确保能直接接触 Mac 和显示器。", 12, NSFontWeightMedium);
    warning.textColor = NSColor.systemOrangeColor;
    [experimentContent addArrangedSubview:warning]; YMFillWidth(warning, experimentContent);
    NSStackView *physicalRow = YMStack(NSUserInterfaceLayoutOrientationHorizontal, 12);
    [physicalRow addArrangedSubview:Label(@"选择实体屏", 12, NSFontWeightRegular)];
    self.physicalChoice = [[NSPopUpButton alloc] init];
    [self.physicalChoice setAccessibilityLabel:@"实验中关闭输出的实体显示器"];
    [self.physicalChoice.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
    [physicalRow addArrangedSubview:self.physicalChoice];
    [physicalRow addArrangedSubview:YMSpacer()];
    self.testButton = ADButton(@"测试 15 秒", self, @selector(startTrial:));
    [physicalRow addArrangedSubview:self.testButton];
    [experimentContent addArrangedSubview:physicalRow]; YMFillWidth(physicalRow, experimentContent);
    NSTextField *experimentNote = Label(@"未确认将尝试自动恢复 · 恢复快捷键 ⌃⌥⌘R · 软件不测量显示器实际功耗", 11, NSFontWeightRegular);
    experimentNote.textColor = NSColor.secondaryLabelColor;
    [experimentContent addArrangedSubview:experimentNote]; YMFillWidth(experimentNote, experimentContent);
    [experiments addArrangedSubview:self.experimentContent]; YMFillWidth(self.experimentContent, experiments);
    [stack addArrangedSubview:experiments]; YMFillWidth(experiments, stack);

    NSStackView *footer = YMStack(NSUserInterfaceLayoutOrientationHorizontal, 12);
    NSTextField *boundary = Label(@"同一登录会话，焦点与键鼠仍共享。", 11, NSFontWeightRegular);
    boundary.textColor = NSColor.tertiaryLabelColor;
    [footer addArrangedSubview:boundary];
    [footer addArrangedSubview:YMSpacer()];
    NSString *versionNumber = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0.2.0";
    NSTextField *version = Label([NSString stringWithFormat:self.previewMode ? @"界面预览 · v%@ · 实验版" : @"v%@ · 实验版", versionNumber], 11, NSFontWeightRegular);
    version.textColor = NSColor.tertiaryLabelColor;
    [footer addArrangedSubview:version];
    [stack addArrangedSubview:footer]; YMFillWidth(footer, stack);
}
- (BOOL)presentationHasVirtualDisplay {
    return self.previewMode ? ![self.previewState isEqualToString:@"empty"] : self.virtualDisplay.isCreated;
}
- (void)presentationSettingsChanged:(id)sender {
    (void)sender;
    [self updateInventory];
}
- (void)primaryAction:(id)sender {
    if (self.previewMode) return;
    if (self.virtualDisplay.isCreated) [self stop:sender]; else [self create:sender];
}
- (void)toggleExperiments:(id)sender {
    (void)sender;
    self.experimentsExpanded = !self.experimentsExpanded;
    [self updateExperimentDisclosure];
}
- (void)updateExperimentDisclosure {
    self.experimentContent.hidden = !self.experimentsExpanded;
    self.experimentToggle.image = [NSImage imageWithSystemSymbolName:self.experimentsExpanded ? @"chevron.down" : @"chevron.right"
                                            accessibilityDescription:nil];
    [self.experimentToggle setAccessibilityLabel:self.experimentsExpanded ? @"收起实验性实体屏输出测试" : @"展开实验性实体屏输出测试"];
    [self.window.contentView layoutSubtreeIfNeeded];
}
- (void)displayParametersChanged:(NSNotification *)notification {
    (void)notification;
    [self updateInventory];
}
- (void)updateWeChatControls {
    if (self.previewMode || !self.windowRecovery) return;
    BOOL trusted = self.windowRecovery.accessibilityTrusted;
    self.wechatPermissionButton.hidden = trusted;
    self.wechatPermissionButton.enabled = !trusted;
    self.wechatPermissionGuide.hidden = trusted;
    self.wechatMoveButton.enabled = self.windowRecovery.canMove && !self.armed && !self.preparing && !self.restoring;
    self.wechatRestoreButton.enabled = self.windowRecovery.canRestore;
    self.wechatStatusLabel.stringValue = trusted ? self.windowRecovery.statusText
        : self.wechatPermissionMessage ?: @"辅助功能未开启 · 开启后才能记住和移动微信窗口。";
    self.wechatStatusLabel.textColor = trusted ? NSColor.secondaryLabelColor : NSColor.labelColor;
}
- (void)wechatPermission:(id)sender {
    (void)sender;
    if (self.previewMode) return;
    NSError *error = nil;
    BOOL opened = [self.windowRecovery openAccessibilitySettings:&error];
    self.wechatPermissionMessage = opened
        ? @"设置已打开，仍需你开启 yomado 开关。授权后这里会自动更新。"
        : error.localizedDescription ?: @"请手动进入系统设置的控制权限页面，开启 yomado。";
    [self updateWeChatControls];
}
- (void)wechatMove:(id)sender {
    (void)sender;
    if (self.previewMode || self.armed || self.preparing || self.restoring) return;
    [self updateInventory];
    NSError *error = nil;
    [self.windowRecovery moveWeChatToVirtual:&error];
    [self updateWeChatControls];
}
- (void)wechatRestore:(id)sender {
    (void)sender;
    if (self.previewMode) return;
    [self updateInventory];
    NSError *error = nil;
    [self.windowRecovery restoreWeChat:&error];
    [self updateWeChatControls];
}
- (void)showWindow:(id)sender {
    (void)sender;
    if (self.previewMode) return;
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}
- (BOOL)windowShouldClose:(NSWindow *)window { [window orderOut:nil]; return NO; }
- (void)updateInventory {
    NSArray *snapshot = self.previewMode ? self.previewSnapshot : DisplaySnapshot();
    if (!self.previewMode) {
        [self.windowRecovery refreshWithVirtualDisplayID:self.virtualDisplay.displayID displaySnapshot:snapshot];
        [self updateWeChatControls];
    }
    BOOL created = [self presentationHasVirtualDisplay];
    BOOL armed = self.previewMode ? [self.previewState isEqualToString:@"trial"] : self.armed;
    CGDirectDisplayID virtualID = self.previewMode ? (created ? 902 : 0) : self.virtualDisplay.displayID;
    NSUInteger physicalCount = 0, virtualCount = 0;
    NSDictionary *owned = nil;
    CGDirectDisplayID selected = [self.physicalChoice.selectedItem.representedObject unsignedIntValue];
    [self.physicalChoice removeAllItems];
    for (NSDictionary *item in snapshot) {
        CGDirectDisplayID ident = [item[@"displayID"] unsignedIntValue];
        NSString *name = item[@"name"] ?: [NSString stringWithFormat:@"显示器 %u", ident];
        BOOL virtualDisplay = [item[@"isVirtual"] boolValue];
        if (virtualDisplay) virtualCount++; else physicalCount++;
        if (ident == virtualID) owned = item;
        if (ident != virtualID && !virtualDisplay) {
            [self.physicalChoice addItemWithTitle:name];
            self.physicalChoice.lastItem.representedObject = @(ident);
            if (ident == selected) [self.physicalChoice selectItem:self.physicalChoice.lastItem];
        }
    }
    self.inventoryLabel.stringValue = [NSString stringWithFormat:@"%lu 块实体屏 · %lu 块虚拟屏 · 显示当前实际排列",
        (unsigned long)physicalCount, (unsigned long)virtualCount];
    self.topologyView.ownedDisplayID = virtualID;
    self.topologyView.snapshot = snapshot;
    self.resolution.enabled = !created;
    self.hiDPIBox.enabled = !created;
    self.createButton.title = created ? @"停止虚拟屏" : @"创建虚拟屏";
    self.createButton.bezelColor = created ? nil : NSColor.controlAccentColor;
    self.createButton.keyEquivalent = created ? @"" : @"\r";
    self.window.defaultButtonCell = created ? nil : (NSButtonCell *)self.createButton.cell;
    self.createButton.enabled = !armed && !self.preparing && !self.restoring && !self.recoveryRequested && !self.layoutChangedForTrial;
    BOOL switchAvailable = self.previewMode ? YES : EnableAPI() && self.hotkey && self.keyHandler;
    self.testButton.enabled = created && !armed && !self.preparing
        && !self.recoveryRequested && !self.layoutChangedForTrial && switchAvailable && self.physicalChoice.numberOfItems > 0;
    self.physicalChoice.enabled = !armed && !self.preparing;
    BOOL recoveryNeeded = armed || self.preparing || self.layoutChangedForTrial || self.recoveryRequested;
    self.restoreButton.enabled = recoveryNeeded;
    self.restoreButton.hidden = !recoveryNeeded;
    self.keepButton.hidden = !(armed && (self.previewMode || self.trialDeadline > 0));
    self.keepButton.enabled = armed && (self.previewMode || self.trialDeadline > 0);
    if (recoveryNeeded) self.experimentsExpanded = YES;
    [self updateExperimentDisclosure];

    if (self.restoring || self.recoveryRequested) {
        self.statusPill.text = @"正在恢复"; self.statusPill.tint = NSColor.systemOrangeColor;
        self.sessionHeadline.stringValue = @"正在恢复实体屏";
        self.sessionCaption.stringValue = @"保留虚拟桌面，直到恢复完成。";
    } else if (armed && !self.preparing && !self.previewMode && self.trialDeadline <= 0) {
        self.statusPill.text = @"虚拟桌面运行中"; self.statusPill.tint = NSColor.controlAccentColor;
        self.sessionHeadline.stringValue = @"工作屏已保留";
        self.sessionCaption.stringValue = @"所选实体屏输出已关闭。软件无法判断显示器真实功耗。";
    } else if (armed || self.preparing) {
        self.statusPill.text = @"实验测试中"; self.statusPill.tint = NSColor.systemOrangeColor;
        self.sessionHeadline.stringValue = @"正在测试输出";
        self.sessionCaption.stringValue = @"在虚拟屏确认操作正常；未确认将尝试自动恢复。";
    } else if (created) {
        self.statusPill.text = @"虚拟屏运行中"; self.statusPill.tint = NSColor.controlAccentColor;
        self.sessionHeadline.stringValue = @"工作屏已就绪";
        self.sessionCaption.stringValue = @"图形桌面已保留。请确认 Agent 能截图并点击目标窗口。";
    } else {
        self.statusPill.text = @"虚拟屏未启动"; self.statusPill.tint = NSColor.secondaryLabelColor;
        self.sessionHeadline.stringValue = @"从一块虚拟屏开始";
        self.sessionCaption.stringValue = @"给截图与键鼠操作保留桌面，实体屏继续供你使用。";
    }
    NSString *resolution = owned ? [NSString stringWithFormat:@"%@ × %@", owned[@"logicalWidth"], owned[@"logicalHeight"]]
        : self.resolution.titleOfSelectedItem;
    self.sessionResolution.stringValue = resolution ?: @"—";
    BOOL assertionsActive = self.previewMode ? created : self.systemAssertion != kIOPMNullAssertionID && self.displayAssertion != kIOPMNullAssertionID;
    self.wakeLabel.stringValue = assertionsActive ? @"已请求" : @"未请求";
    if ([owned[@"isMain"] boolValue]) {
        self.placementLabel.stringValue = @"虚拟屏当前是主屏。普通创建流程不会修改实体主屏。";
    } else if (owned) {
        NSNumber *right = YMPhysicalRightEdge(snapshot);
        self.placementLabel.stringValue = right && [owned[@"x"] doubleValue] >= right.doubleValue
            ? @"虚拟屏位于实体屏右侧 · 只移入指定 Agent 窗口"
            : @"按当前排列显示 · 不自动改动其他屏幕或应用窗口";
    } else {
        self.placementLabel.stringValue = @"新虚拟屏默认放在实体屏右侧，实体主屏保持原位。";
    }
    if (self.previewMode) {
        self.statusLabel.stringValue = armed ? @"实体屏输出测试 · 12 秒后自动恢复" : created ? @"虚拟屏已创建，实体屏仍开启" : @"尚未创建虚拟屏";
        self.detailLabel.stringValue = armed ? @"这是实验性输出测试。恢复按钮和快捷键始终可用；软件无法测量显示器实际功耗。"
            : @"yomado 不会自动搬动其他应用。只把 Agent 需要的窗口移入虚拟屏，你的其他界面留在实体屏。";
        self.wechatStatusLabel.stringValue = @"辅助功能未开启 · 开启后才能记住和移动微信窗口。";
    }
}
- (void)powerAssertions:(BOOL)on {
    if (self.previewMode) return;
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
    if (self.previewMode) return NO;
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
    if (self.previewMode) return NO;
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
    if (self.previewMode) return;
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
    if (self.previewMode) return NO;
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
    if (self.previewMode) return;
    [self writeStateEnding:YES];
    if (self.watchdog.running) [self.watchdog terminate];
    self.watchdog = nil;
    for (NSString *suffix in @[@"", @".ready", @".restored", @".error"])
        [NSFileManager.defaultManager removeItemAtPath:[self.statePath stringByAppendingString:suffix] error:nil];
}
- (BOOL)ensureWatchdog {
    if (self.previewMode) return NO;
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
    if (self.previewMode) return;
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
    if (self.previewMode) return;
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
    [self updateInventory];
}
- (void)restore:(id)sender {
    if (self.previewMode) return;
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
    if (self.previewMode) return;
    (void)timer;
    NSError *windowError = nil;
    [self.windowRecovery pollForRecovery:&windowError];
    [self updateWeChatControls];
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
    if (self.previewMode) return;
    (void)sender;
    if (self.armed || self.preparing || self.layoutChangedForTrial) [self restore:nil];
    if (self.armed || self.preparing || self.restoring || self.layoutChangedForTrial) return;
    if (self.windowRecovery.needsRestoreBeforeRemovingVirtualDisplay) {
        [self updateInventory];
        NSError *error = nil;
        if (![self.windowRecovery restoreWeChat:&error]) {
            self.statusLabel.stringValue = @"保留虚拟屏：请先恢复微信窗口";
            self.detailLabel.stringValue = self.windowRecovery.statusText;
            [self updateWeChatControls];
            return;
        }
    }
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
    if (self.previewMode) return NSTerminateNow;
    (void)sender;
    [self stop:nil];
    if (self.armed || self.preparing || self.restoring || self.layoutChangedForTrial || self.virtualDisplay.isCreated
        || self.windowRecovery.needsRestoreBeforeRemovingVirtualDisplay) {
        [self showWindow:nil];
        return NSTerminateCancel;
    }
    [self writeStateEnding:YES];
    return NSTerminateNow;
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    if (self.previewMode) return;
    (void)notification;
    [NSNotificationCenter.defaultCenter removeObserver:self];
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

// Synthetic fixtures only. This route deliberately never installs ADController as
// the NSApplication delegate, starts a timer/menu/hotkey/watchdog, constructs a
// VDVirtualDisplay, calls live display enumeration, or activates/orders a window.
static NSArray<NSDictionary *> *UIPreviewSnapshot(BOOL created, BOOL trial) {
    NSMutableArray *displays = [NSMutableArray array];
    [displays addObject:@{@"displayID":@900, @"name":@"Studio Display 1", @"x":trial ? @1920 : @0, @"y":@0,
        @"logicalWidth":@2560, @"logicalHeight":@1440, @"isMain":@(!trial), @"isVirtual":@NO, @"isActive":@(!trial), @"isOnline":@YES}];
    [displays addObject:@{@"displayID":@901, @"name":@"Studio Display 2", @"x":trial ? @4480 : @2560, @"y":@0,
        @"logicalWidth":@2560, @"logicalHeight":@1440, @"isMain":@NO, @"isVirtual":@NO, @"isActive":@YES, @"isOnline":@YES}];
    if (created) [displays addObject:@{@"displayID":@902, @"name":@"Agent 虚拟屏", @"x":trial ? @0 : @5120, @"y":@0,
        @"logicalWidth":@1920, @"logicalHeight":@1080, @"isMain":@(trial), @"isVirtual":@YES, @"isActive":@YES, @"isOnline":@YES}];
    return displays;
}
static int PreviewUI(NSString *path, NSString *state, BOOL dark) {
    if (![@[@"empty", @"running", @"trial"] containsObject:state]) {
        fprintf(stderr, "Preview state must be empty, running, or trial.\n");
        return 64;
    }
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSAppearance *appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    NSApp.appearance = appearance;
    ADController *controller = [[ADController alloc] init];
    controller.previewMode = YES;
    controller.previewState = state;
    controller.previewSnapshot = UIPreviewSnapshot(![state isEqualToString:@"empty"], [state isEqualToString:@"trial"]);
    [controller buildWindow];
    controller.window.appearance = appearance;
    [controller updateInventory];
    NSView *content = controller.window.contentView;
    [content layoutSubtreeIfNeeded];
    NSScrollView *scroll = (NSScrollView *)content.subviews.firstObject;
    CGFloat height = MAX(820, ceil(scroll.documentView.frame.size.height));
    [controller.window setContentSize:NSMakeSize(920, height)];
    [content layoutSubtreeIfNeeded];
    // Native controls may settle their internal layers on a later run-loop turn.
    // Only this hidden fixture window exists in the preview process.
    for (NSUInteger pass = 0; pass < 3; pass++) {
        [content displayIfNeeded];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        [content layoutSubtreeIfNeeded];
    }
    NSBitmapImageRep *bitmap = [content bitmapImageRepForCachingDisplayInRect:content.bounds];
    if (!bitmap) { fprintf(stderr, "Could not allocate UI preview bitmap.\n"); return 1; }
    [content cacheDisplayInRect:content.bounds toBitmapImageRep:bitmap];
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSError *error = nil;
    if (!png || ![png writeToFile:path options:NSDataWritingAtomic error:&error]) {
        fprintf(stderr, "Could not write UI preview (%s, %ld).\n", (error.domain ?: @"render").UTF8String, (long)error.code);
        return 1;
    }
    printf("%s\n", JSONText(@{@"renderedFrom":@"synthetic-ui-fixtures", @"state":state,
        @"appearance":dark ? @"dark" : @"light", @"pixelsWide":@(bitmap.pixelsWide), @"pixelsHigh":@(bitmap.pixelsHigh)}).UTF8String);
    [controller.window close];
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--preview-ui") == 0) {
            if (argc < 3 || argc > 5 || (argc == 5 && strcmp(argv[4], "light") != 0 && strcmp(argv[4], "dark") != 0)) {
                fprintf(stderr, "Usage: Yomado --preview-ui <png-path> [empty|running|trial] [light|dark]\n");
                return 64;
            }
            return PreviewUI([NSString stringWithUTF8String:argv[2]],
                argc > 3 ? [NSString stringWithUTF8String:argv[3]] : @"running", argc > 4 && strcmp(argv[4], "dark") == 0);
        }
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
