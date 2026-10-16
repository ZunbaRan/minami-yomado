#import "DesktopPreview.h"
#import "Common.h"
#import "VDVirtualDisplay.h"
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <AVFoundation/AVFoundation.h>

@interface YMPreviewPanel : NSPanel
@end
@implementation YMPreviewPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface YMDesktopPreview () <SCStreamOutput, SCStreamDelegate, NSWindowDelegate>
@property(nonatomic) CGDirectDisplayID displayID;
@property(nonatomic) YMPreviewPanel *panel;
@property(nonatomic) AVSampleBufferDisplayLayer *video;
@property(nonatomic) NSTextField *label;
@property(nonatomic) SCStream *stream;
@property(nonatomic) NSString *phase;
@property(nonatomic) NSString *failure;
@property(nonatomic) NSUInteger frames;
@property(nonatomic) CFTimeInterval lastFrame;
@property(nonatomic) NSInteger outputWidth;
@property(nonatomic) NSInteger outputHeight;
@property(nonatomic) NSInteger fps;
@property(nonatomic) BOOL cursor;
@property(nonatomic) NSTimer *monitor;
@end

@implementation YMDesktopPreview
- (instancetype)initWithDisplayID:(CGDirectDisplayID)displayID name:(NSString *)name options:(NSDictionary *)options {
    if (!(self = [super init])) return nil;
    _displayID = displayID; _phase = @"starting";
    _fps = [options[@"fps"] ?: @30 integerValue]; _outputWidth = [options[@"output_width"] ?: @1280 integerValue];
    _cursor = [options[@"shows_cursor"] ?: @YES boolValue];
    if (_fps < 1 || _fps > 60 || _outputWidth < 320 || _outputWidth > 3840) YMThrow(@"invalid_argument", @"fps must be 1–60 and output_width 320–3840.");
    if (!CGPreflightScreenCaptureAccess()) YMThrow(@"screen_recording_required", @"Enable Screen Recording for the responsible host/helper in macOS Settings, then retry.");
    @try {
        YMMain(^id{
            self.panel = [[YMPreviewPanel alloc] initWithContentRect:NSMakeRect(0, 0, 480, 270)
                styleMask:NSWindowStyleMaskNonactivatingPanel | NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                backing:NSBackingStoreBuffered defer:NO];
            self.panel.title = [@"Yomado Workspace — " stringByAppendingString:name];
            self.panel.level = NSFloatingWindowLevel; self.panel.hidesOnDeactivate = NO;
            self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
            self.panel.releasedWhenClosed = NO; self.panel.delegate = self;
            self.panel.contentView.wantsLayer = YES; self.panel.contentView.layer.backgroundColor = NSColor.blackColor.CGColor;
            self.video = [AVSampleBufferDisplayLayer layer]; self.video.videoGravity = AVLayerVideoGravityResizeAspect;
            [self.panel.contentView.layer addSublayer:self.video];
            self.label = [NSTextField labelWithString:@"Starting desktop capture…"];
            self.label.textColor = NSColor.whiteColor; self.label.alignment = NSTextAlignmentCenter;
            self.label.frame = NSMakeRect(10, 10, 450, 44); self.label.autoresizingMask = NSViewWidthSizable;
            [self.panel.contentView addSubview:self.label];
            return nil;
        });
        [self configure:options];
        __block SCShareableContent *content; __block NSError *captureError;
        dispatch_semaphore_t ready = dispatch_semaphore_create(0);
        [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:NO completionHandler:^(SCShareableContent *value, NSError *error) {
            content = value; captureError = error; dispatch_semaphore_signal(ready);
        }];
        if (dispatch_semaphore_wait(ready, dispatch_time(DISPATCH_TIME_NOW, 10*NSEC_PER_SEC))) YMThrow(@"capture_timeout", @"ScreenCaptureKit enumeration timed out. Check capture permissions.");
        YMCheck(content != nil, captureError);
        SCDisplay *target;
        for (SCDisplay *display in content.displays) if (display.displayID == displayID) { target = display; break; }
        if (!target) YMThrow(@"display_not_capturable", @"The exact virtual display was not returned by ScreenCaptureKit.");
        NSMutableArray *excluded = [NSMutableArray array];
        for (SCRunningApplication *app in content.applications) if (app.processID == getpid()) [excluded addObject:app];
        SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:target excludingApplications:excluded exceptingWindows:@[]];
        if (@available(macOS 14.2, *)) filter.includeMenuBar = YES;
        _outputHeight = MAX(1, (NSInteger)llround(_outputWidth * target.frame.size.height / target.frame.size.width));
        if (_outputHeight > 3840) {
            _outputWidth = MAX(1, (NSInteger)llround(_outputWidth * 3840.0 / _outputHeight)); _outputHeight = 3840;
        }
        SCStreamConfiguration *config = [SCStreamConfiguration new];
        config.width = (size_t)_outputWidth; config.height = (size_t)_outputHeight;
        config.minimumFrameInterval = CMTimeMake(1, (int32_t)_fps); config.queueDepth = 3;
        config.pixelFormat = kCVPixelFormatType_32BGRA; config.showsCursor = _cursor; config.capturesAudio = NO;
        _stream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:self];
        NSError *e;
        YMCheck([_stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:dispatch_queue_create("workspace.frames", DISPATCH_QUEUE_SERIAL) error:&e], e);
        __weak typeof(self) weakSelf = self;
        [_stream startCaptureWithCompletionHandler:^(NSError *error) {
            if (error) dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf fail:error.localizedDescription]; });
        }];
        YMMain(^id{
            [self.panel orderFrontRegardless];
            self.monitor = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
                (void)timer;
                if (!CGDisplayIsActive(displayID)) { [weakSelf fail:@"Virtual display is no longer active."]; return; }
                // A user may drag the viewer; keep it off its source display.
                CGRect source = CGDisplayBounds(displayID);
                NSRect f = weakSelf.panel.frame;
                CGFloat top = CGDisplayBounds(CGMainDisplayID()).size.height;
                CGRect screenFrame = CGRectMake(f.origin.x, top-NSMaxY(f), f.size.width, f.size.height);
                if (CGRectIntersectsRect(source, screenFrame)) {
                    @try { [weakSelf placeOnPhysical:@{}]; } @catch (NSException *e) { [weakSelf fail:e.reason]; }
                }
            }];
            return nil;
        });
    } @catch (NSException *e) { [self close]; @throw e; }
    return self;
}
- (void)placeOnPhysical:(NSDictionary *)options {
    NSScreen *physical;
    for (NSScreen *screen in NSScreen.screens) {
        CGDirectDisplayID ident = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        if (ident == CGMainDisplayID() && ![VDVirtualDisplay isVirtualDisplay:ident]) { physical = screen; break; }
    }
    if (!physical) YMThrow(@"physical_main_required", @"No physical main screen is available for the preview.");
    NSRect visible = physical.visibleFrame;
    CGFloat w = [options[@"width"] ?: @(self.panel.frame.size.width) doubleValue];
    CGFloat h = [options[@"height"] ?: @(self.panel.frame.size.height) doubleValue];
    if (w < 240 || h < 160 || w > visible.size.width || h > visible.size.height) YMThrow(@"invalid_argument", @"Preview dimensions must fit the physical display (minimum 240×160).");
    CGFloat x = [options[@"x"] ?: @(NSMaxX(visible)-w-16) doubleValue];
    CGFloat top = CGDisplayBounds(CGMainDisplayID()).size.height;
    CGFloat y = options[@"y"] ? top-[options[@"y"] doubleValue]-h : NSMaxY(visible)-h-16;
    NSRect frame = NSMakeRect(x, y, w, h);
    if (!NSContainsRect(visible, frame)) YMThrow(@"invalid_argument", @"Preview frame must stay within the physical main display's usable area.");
    [self.panel setFrame:frame display:YES]; self.video.frame = self.panel.contentView.bounds;
}
- (void)configure:(NSDictionary *)options { YMMain(^id{ [self placeOnPhysical:options]; return nil; }); }
- (void)windowDidResize:(NSNotification *)notification { (void)notification; self.video.frame = self.panel.contentView.bounds; }
- (void)windowWillClose:(NSNotification *)notification { (void)notification; [self close]; }
- (void)fail:(NSString *)reason {
    if ([self.phase isEqual:@"closed"] || [self.phase isEqual:@"error"]) return;
    self.phase = @"error"; self.failure = reason;
    [self.video flushAndRemoveImage]; self.label.stringValue = reason; self.label.hidden = NO;
    [self.monitor invalidate]; self.monitor = nil;
    [self.stream stopCaptureWithCompletionHandler:^(NSError *e) { (void)e; }];
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    (void)stream; dispatch_async(dispatch_get_main_queue(), ^{ [self fail:error.localizedDescription]; });
}
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    (void)stream;
    if (type != SCStreamOutputTypeScreen || !CMSampleBufferIsValid(sample)) return;
    NSArray *attachments = (__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sample, NO);
    NSNumber *number = attachments.firstObject[SCStreamFrameInfoStatus]; if (!number) return;
    SCFrameStatus status = number.integerValue;
    if (status == SCFrameStatusIdle) return;
    if (status != SCFrameStatusComplete) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (![self.phase isEqual:@"closed"] && ![self.phase isEqual:@"error"] && status != SCFrameStatusStarted) {
                self.phase = @"suspended"; [self.video flushAndRemoveImage]; self.label.stringValue = @"Desktop capture is suspended"; self.label.hidden = NO;
            }
        }); return;
    }
    CFArrayRef attrs = CMSampleBufferGetSampleAttachmentsArray(sample, YES);
    if (attrs && CFArrayGetCount(attrs)) CFDictionarySetValue((CFMutableDictionaryRef)CFArrayGetValueAtIndex(attrs, 0), kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
    // Synchronous handoff bounds queued work; the sample remains alive throughout.
    dispatch_sync(dispatch_get_main_queue(), ^{
        if ([self.phase isEqual:@"closed"] || [self.phase isEqual:@"error"]) return;
        if (self.video.status == AVQueuedSampleBufferRenderingStatusFailed) [self.video flush];
        [self.video enqueueSampleBuffer:sample]; self.label.hidden = YES;
        self.frames++; self.lastFrame = CACurrentMediaTime(); self.phase = @"live";
    });
}
- (NSDictionary *)status {
    return YMMain(^id{
        NSRect f = self.panel.frame; CGFloat top = CGDisplayBounds(CGMainDisplayID()).size.height;
        return @{@"display_id":@(self.displayID), @"window_id":@(self.panel.windowNumber), @"state":self.phase,
            @"frames":@(self.frames), @"last_frame_age_ms":self.lastFrame ? @((CACurrentMediaTime()-self.lastFrame)*1000) : NSNull.null,
            @"error":self.failure ?: (id)NSNull.null, @"fps_limit":@(self.fps), @"output_width":@(self.outputWidth), @"output_height":@(self.outputHeight),
            @"shows_cursor":@(self.cursor), @"bounds":YMRect(CGRectMake(f.origin.x, top-NSMaxY(f), f.size.width, f.size.height))};
    });
}
- (void)close {
    YMMain(^id{
        if ([self.phase isEqual:@"closed"]) return nil;
        self.phase = @"closed"; [self.monitor invalidate]; self.monitor = nil;
        self.panel.delegate = nil; [self.panel close]; [self.video flushAndRemoveImage];
        [self.stream stopCaptureWithCompletionHandler:^(NSError *e) { (void)e; }];
        self.stream = nil;
        return nil;
    });
}
@end
