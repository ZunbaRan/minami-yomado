// Executes production controller logic with fake display/topology boundaries.
// No NSApplication, CoreGraphics operations, window creation, defaults or IOPM.
#define main YMIgnoredApplicationMain
#import "Yomado.m"
#undef main

@interface YMFakeDisplay : VDVirtualDisplay
@property BOOL live;
@property BOOL createResult;
@property NSUInteger creates;
@property NSUInteger destroys;
@property CGDirectDisplayID fixtureID;
@end
@implementation YMFakeDisplay
- (instancetype)init { if ((self = [super init])) _createResult = YES; return self; }
- (BOOL)isCreated { return self.live; }
- (CGDirectDisplayID)displayID { return self.live ? self.fixtureID : 0; }
- (BOOL)createWithWidth:(NSUInteger)w height:(NSUInteger)h hiDPI:(BOOL)hiDPI name:(NSString *)name error:(NSError **)error {
    (void)w; (void)h; (void)hiDPI; (void)name; self.creates++;
    self.live = self.createResult;
    if (!self.createResult && error) *error = [NSError errorWithDomain:@"fixture" code:1 userInfo:nil];
    return self.createResult;
}
- (void)destroy { self.destroys++; self.live = NO; }
@end

@interface YMFakeTopology : NSObject
@property BOOL captureResult;
@property BOOL configureResult;
@property BOOL restoreResult;
@property BOOL extended;
@property NSUInteger captures;
@property NSUInteger configurations;
@property NSUInteger restorations;
@property CGDirectDisplayID lastRemoved;
@property YMDisplayTopologySnapshot *snapshot;
@property(copy) void (^duringCapture)(void);
@property(copy) void (^duringConfigure)(void);
@property(copy) void (^duringRestore)(void);
@end
@implementation YMFakeTopology
- (instancetype)init {
    if ((self = [super init])) { _captureResult = YES; _configureResult = YES; _restoreResult = YES; _extended = YES; _snapshot = [YMDisplayTopologySnapshot new]; }
    return self;
}
- (YMDisplayTopologySnapshot *)captureSnapshotWithError:(NSError **)error {
    self.captures++; if (self.duringCapture) self.duringCapture();
    if (!self.captureResult && error) *error = [NSError errorWithDomain:@"fixture" code:2 userInfo:nil];
    return self.captureResult ? self.snapshot : nil;
}
- (BOOL)configureAndVerifyNewDisplay:(CGDirectDisplayID)d width:(NSUInteger)w height:(NSUInteger)h hiDPI:(BOOL)hi baseline:(YMDisplayTopologySnapshot *)s error:(NSError **)error {
    (void)d; (void)w; (void)h; (void)hi; (void)s; self.configurations++;
    if (self.duringConfigure) self.duringConfigure();
    if (!self.configureResult && error) *error = [NSError errorWithDomain:@"fixture" code:3 userInfo:nil];
    return self.configureResult;
}
- (BOOL)restoreAndVerifySnapshot:(YMDisplayTopologySnapshot *)s excludingDisplayID:(CGDirectDisplayID)d error:(NSError **)error {
    (void)s; self.restorations++; self.lastRemoved = d;
    if (self.duringRestore) self.duringRestore();
    if (!self.restoreResult && error) *error = [NSError errorWithDomain:@"fixture" code:4 userInfo:nil];
    return self.restoreResult;
}
- (BOOL)isExtendedTarget:(CGDirectDisplayID)d width:(NSUInteger)w height:(NSUInteger)h hiDPI:(BOOL)hi {
    (void)d; (void)w; (void)h; (void)hi; return self.extended;
}
@end

@interface YMFakeController : ADController
@property NSUInteger inventoryUpdates;
@property NSUInteger saves;
@property NSUInteger reports;
@property BOOL powerFails;
@property BOOL simulateFinalRemovalRecoveryFailure;
@property NSUInteger stopCalls;
@property NSUInteger showCalls;
@end
@implementation YMFakeController
- (void)updateInventory { self.inventoryUpdates++; }
- (void)saveDisplayProfiles { self.saves++; }
- (void)reportTopologyError:(NSError *)error { (void)error; self.reports++; }
- (void)powerAssertions:(BOOL)on { self.systemAssertion = self.displayAssertion = on && !self.powerFails ? 1 : 0; }
- (BOOL)restoreApplicationsForDisplayID:(CGDirectDisplayID)displayID { (void)displayID; return YES; }
- (void)showWindow:(id)sender { (void)sender; self.showCalls++; }
- (BOOL)writeStateEnding:(BOOL)end { (void)end; return YES; }
- (void)stop:(id)sender {
    (void)sender; self.stopCalls++;
    // The termination decision is production logic. This boundary models the
    // actual stop outcome: the last owned output is gone, recovery still fails.
    // It deliberately avoids the real stop method's WindowServer calls.
    if (self.simulateFinalRemovalRecoveryFailure) {
        CGDirectDisplayID removed = self.virtualDisplay.displayID;
        self.selectedProfile.topologyVerified = NO;
        [self.virtualDisplay destroy];
        YMDisplayTopologySnapshot *snapshot = [(YMFakeTopology *)self.displayTopology snapshot];
        [self recoverTopology:snapshot removedID:removed error:nil];
    }
}
@end

static NSUInteger Tests, Failures;
static void Expect(BOOL value, const char *name) { Tests++; if (!value) { Failures++; fprintf(stderr,"FAIL %s\n",name); } }
static YMFakeController *Controller(YMFakeTopology **t, YMFakeDisplay **d, YMManagedDisplay **p, YMManagedDisplay **s) {
    YMFakeController *c = [YMFakeController new];
    *t = [YMFakeTopology new]; c.displayTopology = (YMDisplayTopology *)*t;
    *d = [YMFakeDisplay new]; (*d).fixtureID = 202;
    *p = [YMManagedDisplay new]; (*p).width=800; (*p).height=600; (*p).ordinal=2; (*p).friendlyName=@"fixture"; (*p).display=*d;
    YMFakeDisplay *older = [YMFakeDisplay new]; older.live = YES; older.fixtureID=101;
    *s = [YMManagedDisplay new]; (*s).width=800; (*s).height=600; (*s).display=older; (*s).topologyVerified=YES;
    c.displayProfiles=[NSMutableArray arrayWithArray:@[*s,*p]]; c.selectedProfile=*p; c.virtualDisplay=*d;
    return c;
}
int main(void) {
    @autoreleasepool {
        Expect(NSApp == nil,"tests begin without NSApplication");
        YMFakeTopology *t; YMFakeDisplay *d; YMManagedDisplay *p,*s;
        YMFakeController *c = Controller(&t,&d,&p,&s);
        __weak YMFakeController *weakC=c; __weak YMManagedDisplay *weakP=p;
        t.duringCapture=^{Expect(weakC.displayOperationInProgress,"busy begins before capture");};
        t.duringConfigure=^{Expect(weakC.displayOperationInProgress,"busy during configure"); Expect(![weakC canMoveIntoProfile:weakP],"no admission during configure");};
        [c create:nil];
        Expect(d.creates==1&&d.destroys==0,"success creates once, retains target");
        Expect(p.topologyVerified&&[c canMoveIntoProfile:p],"success opens real admission gate");
        Expect(c.saves==1&&!c.displayOperationInProgress,"success saved and busy released");
        Expect(s.display.isCreated&&[(YMFakeDisplay *)s.display destroys]==0,"success preserves older object");
        t.extended=NO; Expect(![c canMoveIntoProfile:p],"later mirror/mode mismatch closes admission");

        c=Controller(&t,&d,&p,&s); t.configureResult=NO;
        weakC=c; weakP=p;
        t.duringRestore=^{Expect(weakC.displayOperationInProgress,"busy through rollback");Expect(![weakC canMoveIntoProfile:weakP],"no admission during rollback");};
        [c create:nil];
        Expect(d.creates==1&&d.destroys==1&&!d.live,"configuration failure destroys only new target");
        Expect(t.restorations==1&&t.lastRemoved==202,"rollback receives exact removed ID");
        Expect(!p.topologyVerified&&!c.topologyRecoverySnapshot&&!c.displayOperationInProgress,"verified rollback clears busy without admitting target");
        Expect(c.saves==0&&c.reports==1,"failed target not persisted as success");
        Expect(s.display.isCreated&&[(YMFakeDisplay *)s.display destroys]==0,"rollback preserves older object");

        c=Controller(&t,&d,&p,&s); t.configureResult=NO; t.restoreResult=NO; [c create:nil];
        Expect(c.topologyRecoverySnapshot==t.snapshot&&c.topologyRecoveryRemovedID==202,"failed recovery retains snapshot and target ID");
        Expect(![c canMoveIntoProfile:s],"recovery failure gates sibling admission too");
        NSUInteger priorCreates=d.creates; [c create:nil]; Expect(d.creates==priorCreates,"pending recovery blocks subsequent creation");
        t.restoreResult=YES; [c retryTopologyRecovery:nil];
        Expect(!c.topologyRecoverySnapshot&&!c.topologyRecoveryRemovedID,"successful retry clears pending state");
        Expect([c canMoveIntoProfile:s],"recovery retry restores verified sibling admission");
        Expect(![c canMoveIntoProfile:p],"recovery retry does not admit removed target");

        c=Controller(&t,&d,&p,&s); t.captureResult=NO; [c create:nil];
        Expect(d.creates==0&&t.configurations==0&&t.restorations==0,"incomplete baseline causes no creation or mutation");
        Expect(!p.topologyVerified&&!c.displayOperationInProgress,"capture failure leaves target denied and idle");
        c=Controller(&t,&d,&p,&s); d.createResult=NO; [c create:nil];
        Expect(d.creates==1&&t.configurations==0&&t.restorations==1,"private API create failure still verifies original baseline");
        Expect(d.destroys==0&&s.display.isCreated,"create failure never destroys older display");
        c=Controller(&t,&d,&p,&s); c.powerFails=YES; [c create:nil];
        Expect(d.destroys==1&&t.restorations==1&&!p.topologyVerified,"power assertion failure rolls new output back");
        Expect(s.display.isCreated,"power failure preserves sibling");
        c=Controller(&t,&d,&p,&s);
        c.displayProfiles=[NSMutableArray arrayWithObject:s]; c.selectedProfile=s; c.virtualDisplay=s.display;
        c.simulateFinalRemovalRecoveryFailure=YES; t.restoreResult=NO;
        // The production method explicitly ignores sender; no app singleton is created.
        NSApplication *unusedSender=(NSApplication *)(id)[NSObject new];
        NSApplicationTerminateReply reply=[c applicationShouldTerminate:unusedSender];
        Expect(reply==NSTerminateCancel,"last-output recovery failure cancels termination");
        Expect(!s.display.isCreated&&c.stopCalls==1,"termination observes removed final output");
        Expect(c.topologyRecoverySnapshot==t.snapshot,"termination retains failed recovery snapshot");
        Expect(c.showCalls==1,"failed final recovery exposes recovery controls");
        reply=[c applicationShouldTerminate:unusedSender];
        Expect(reply==NSTerminateCancel&&c.stopCalls==1,"repeated quit retries recovery without another destroy");
        t.restoreResult=YES; reply=[c applicationShouldTerminate:unusedSender];
        Expect(reply==NSTerminateNow&&!c.topologyRecoverySnapshot,"verified recovery permits subsequent quit");
        Expect(NSApp == nil,"all controller tests leave NSApplication uninitialized");
        printf("Controller boundary tests: %lu passed, %lu failed; no GUI or display calls executed.\n",(unsigned long)(Tests-Failures),(unsigned long)Failures);
        return Failures?1:0;
    }
}
