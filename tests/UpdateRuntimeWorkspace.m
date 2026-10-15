#import "UpdateRuntimeWorkspace.h"
#import "VDVirtualDisplay.h"
#import "YMDisplayTopology.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

static BOOL FFail(NSError **error, NSInteger code, NSString *description) {
    if (error) *error=[NSError errorWithDomain:@"fixture.occupied-workspace" code:code
        userInfo:@{NSLocalizedDescriptionKey:description}];
    return NO;
}
static BOOL FFrameEqual(NSDictionary *a, NSDictionary *b) {
    if (!a || !b) return NO;
    for (NSString *key in @[@"x",@"y",@"width",@"height"])
        if (!a[key] || !b[key] || fabs([a[key] doubleValue]-[b[key] doubleValue])>1) return NO;
    return YES;
}
static NSDictionary *FIdentity(pid_t pid, NSError **error) {
    AXUIElementRef app=AXUIElementCreateApplication(pid); CFTypeRef raw=NULL;
    AXError status=AXUIElementCopyAttributeValue(app,kAXWindowsAttribute,&raw); CFRelease(app);
    id windows=CFBridgingRelease(raw);
    if (status!=kAXErrorSuccess || ![windows isKindOfClass:NSArray.class] || [windows count]!=1) {
        FFail(error,1,@"Expected exactly one ordinary fixture window."); return nil;
    }
    NSDictionary *identity=YMUpdateIdentityForWindowElement([windows firstObject]);
    if (!identity) FFail(error,2,@"Could not resolve the exact fixture process and window.");
    return identity;
}
@interface YMUpdateRuntimeWorkspace ()
@property(nonatomic, copy) NSString *directory;
@property(nonatomic) pid_t workPID;
@property(nonatomic) pid_t probePID;
@property(nonatomic, strong) id<YMUpdateWorkspaceRecoveryBackend> backend;
@property(nonatomic, copy) void (^record)(NSString *, NSDictionary *);
@property(nonatomic, strong) VDVirtualDisplay *display;
@property(nonatomic, strong) YMDisplayTopology *topology;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, copy) NSDictionary *baseline;
@end
@implementation YMUpdateRuntimeWorkspace
- (instancetype)initWithDirectory:(NSString *)directory workPID:(pid_t)workPID probePID:(pid_t)probePID
    backend:(id<YMUpdateWorkspaceRecoveryBackend>)backend record:(void (^)(NSString *, NSDictionary *))record {
    self=[super init]; if (self) {
        _directory=directory; _workPID=workPID; _probePID=probePID; _backend=backend; _record=[record copy];
        _topology=[YMDisplayTopology new]; _queue=dispatch_queue_create("fixture.occupied-topology",DISPATCH_QUEUE_SERIAL);
        _display=[[VDVirtualDisplay alloc] initWithSerialNumber:829401];
    } return self;
}
- (NSArray<NSDictionary *> *)profiles {
    if (!self.display.isCreated) return @[];
    return @[@{@"ordinal":@1,@"displayID":@(self.display.displayID),@"width":@1280,@"height":@800,@"hiDPI":@NO}];
}
- (BOOL)captureNamed:(NSString *)name error:(NSError **)error {
    CGDirectDisplayID displays[64]; uint32_t count=0; NSUInteger index=NSNotFound;
    if (CGGetActiveDisplayList(64,displays,&count)!=kCGErrorSuccess || count>=64)
        return FFail(error,8,@"Cannot identify the fixture screen for pixel evidence.");
    for (uint32_t i=0;i<count;i++) if (displays[i]==self.display.displayID) index=i+1;
    if (index==NSNotFound) return FFail(error,8,@"The fixture screen disappeared before capture.");
    NSTask *capture=[NSTask new]; capture.executableURL=[NSURL fileURLWithPath:@"/usr/sbin/screencapture"];
    capture.arguments=@[@"-x",@"-D",[@(index) stringValue],[self.directory stringByAppendingPathComponent:name]];
    if (![capture launchAndReturnError:error]) return NO;
    [capture waitUntilExit];
    self.record(@"occupied-pixel-capture",@{@"name":name,@"status":@(capture.terminationStatus),@"displayID":@(self.display.displayID),@"displayIndex":@(index)});
    return capture.terminationStatus==0 || FFail(error,8,@"The real virtual-screen screenshot was not captured.");
}
- (NSString *)baselinePath { return [self.directory stringByAppendingPathComponent:@"workspace-baseline.json"]; }
- (void)createWithSavedBounds:(NSDictionary *)savedBounds completion:(void (^)(BOOL,NSError *))completion {
    // Production requires AppKit to keep processing display notifications while
    // its bounded CoreGraphics transactions execute on a serial worker queue.
    dispatch_async(self.queue, ^{
        NSError *error=nil;
        YMDisplayTopologySnapshot *before=[self.topology captureSnapshotWithError:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *creationError=error;
            if (!before || ![self.display createWithWidth:1280 height:800 hiDPI:NO name:@"Update acceptance workspace" error:&creationError]) {
                completion(NO,creationError); return;
            }
            CGDirectDisplayID ID=self.display.displayID;
            dispatch_async(self.queue, ^{
                NSError *configureError=nil;
                BOOL ready=[self.topology configureAndVerifyNewDisplay:ID width:1280 height:800 hiDPI:NO baseline:before error:&configureError];
                if (ready && savedBounds) {
                    YMDisplayTopologySnapshot *layout=[self.topology captureSnapshotWithError:&configureError];
                    ready=layout && [self.topology positionOwnedDisplays:@{@(ID):savedBounds} baseline:layout error:&configureError];
                }
                dispatch_async(dispatch_get_main_queue(), ^{ completion(ready,configureError); });
            });
        });
    });
}
- (void)prepareOccupiedWorkspace:(void (^)(BOOL,NSError *))completion {
    NSError *error=nil;
    self.record(@"occupied-preflight",@{@"accessibilityTrusted":@(AXIsProcessTrusted()),@"virtualAPIAvailable":@(VDVirtualDisplay.isAPIAvailable)});
    if (!AXIsProcessTrusted() || !VDVirtualDisplay.isAPIAvailable) {
        FFail(&error,3,@"Guest Accessibility or virtual-display support is unavailable."); completion(NO,error); return;
    }
    NSDictionary *workIdentity=FIdentity(self.workPID,&error), *probeIdentity=FIdentity(self.probePID,&error);
    NSDictionary *work=workIdentity ? [self.backend readWindow:workIdentity error:&error] : nil;
    NSDictionary *probe=probeIdentity ? [self.backend readWindow:probeIdentity error:&error] : nil;
    NSDictionary *state=[self.backend captureWithProfiles:@[] error:&error];
    if (!work || !probe || !state) { completion(NO,error); return; }
    [self createWithSavedBounds:nil completion:^(BOOL ready,NSError *creationError) {
        NSError *failure=creationError;
        if (!ready) { completion(NO,failure); return; }
        CGRect bounds=CGDisplayBounds(self.display.displayID);
        NSMutableDictionary *destination=[work[@"frame"] mutableCopy];
        destination[@"x"]=@(bounds.origin.x+100); destination[@"y"]=@(bounds.origin.y+120);
        if (![self.backend moveWindow:workIdentity fromFrame:work[@"frame"] toFrame:destination error:&failure]) {
            completion(NO,failure); return;
        }
        NSDictionary *after=[self.backend captureWithProfiles:self.profiles error:&failure];
        NSDictionary *probeAfter=[self.backend readWindow:probeIdentity error:&failure];
        if (!after || [after[@"windows"] count]!=1 ||
            ![after[@"windows"][0][@"identity"] isEqual:workIdentity] ||
            !FFrameEqual(probeAfter[@"frame"],probe[@"frame"])) {
            FFail(&failure,4,@"Owned inventory or untouched physical probe did not match."); completion(NO,failure); return;
        }
        NSMutableArray *unowned=[after[@"displays"] mutableCopy];
        [unowned filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item,NSDictionary *bindings) {
            (void)bindings; return ![item[@"displayID"] isEqual:@(self.display.displayID)];
        }]];
        if (![unowned isEqual:state[@"displays"]]) {
            FFail(&failure,5,@"Creating the workspace changed an unowned display."); completion(NO,failure); return;
        }
        self.baseline=@{@"work":after[@"windows"][0],@"probe":probe,@"unownedDisplays":state[@"displays"],@"profiles":self.profiles};
        NSData *data=[NSJSONSerialization dataWithJSONObject:self.baseline options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&failure];
        if (!data || ![data writeToFile:self.baselinePath options:NSDataWritingAtomic error:&failure]) { completion(NO,failure); return; }
        self.record(@"occupied-ready",self.baseline);
        BOOL captured=[self captureNamed:@"occupied-before.png" error:&failure]; completion(captured,failure);
    }];
}
- (void)recreateProfiles:(NSArray<NSDictionary *> *)profiles completion:(void (^)(BOOL,NSError *))completion {
    NSError *error=nil; NSData *data=[NSData dataWithContentsOfFile:self.baselinePath options:0 error:&error];
    self.baseline=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
    NSDictionary *saved=profiles.count==1 ? profiles.firstObject : nil;
    if (!self.baseline || ![saved[@"ordinal"] isEqual:@1] || ![saved[@"width"] isEqual:@1280] ||
        ![saved[@"height"] isEqual:@800] || [saved[@"hiDPI"] boolValue] || !saved[@"bounds"]) {
        FFail(&error,6,@"The occupied restart fixture did not receive its exact saved profile."); completion(NO,error); return;
    }
    self.record(@"occupied-recreate",@{@"savedProfiles":profiles});
    [self createWithSavedBounds:saved[@"bounds"] completion:completion];
}
- (BOOL)verifyRestoredWorkspace:(NSError **)error {
    NSDictionary *state=[self.backend captureWithProfiles:self.profiles error:error];
    NSDictionary *probe=[self.backend readWindow:self.baseline[@"probe"][@"identity"] error:error];
    NSDictionary *work=[self.backend readWindow:self.baseline[@"work"][@"identity"] error:error];
    if (!state || !probe || !work) return NO;
    NSMutableArray *unowned=[state[@"displays"] mutableCopy];
    [unowned filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item,NSDictionary *bindings) {
        (void)bindings; return ![item[@"displayID"] isEqual:@(self.display.displayID)];
    }]];
    BOOL matches=[state[@"windows"] count]==1 &&
        [state[@"windows"][0][@"identity"] isEqual:self.baseline[@"work"][@"identity"]] &&
        [probe[@"identity"] isEqual:self.baseline[@"probe"][@"identity"]] &&
        FFrameEqual(work[@"frame"],self.baseline[@"work"][@"frame"]) &&
        FFrameEqual(probe[@"frame"],self.baseline[@"probe"][@"frame"]) &&
        [unowned isEqual:self.baseline[@"unownedDisplays"]];
    self.record(@"occupied-verified",@{@"matches":@(matches),@"currentWork":work,@"currentProbe":probe,
        @"currentState":state,@"currentProfiles":self.profiles});
    if (!matches) return FFail(error,7,@"Exact surviving window identity, geometry or physical probe changed.");
    return [self captureNamed:@"occupied-after.png" error:error];
}
@end
