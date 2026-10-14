// Disposable hosted-session adapter: production create/stop/queue are unchanged.
// Persistence and application-window recovery are omitted because this fixture
// owns no managed app windows and must not touch runner preferences.
#define main YMUnusedApplicationMain
#import "Yomado.m"
#undef main

@interface YMCIHostedController : ADController
@property NSMutableArray<NSDictionary *> *fixtureErrors;
@end
@implementation YMCIHostedController
- (void)updateInventory {}
- (void)saveDisplayProfiles {}
- (void)finishWatchdog {}
- (BOOL)restoreApplicationsForDisplayID:(CGDirectDisplayID)displayID { (void)displayID; return YES; }
- (void)reportTopologyError:(NSError *)error {
    if (!self.fixtureErrors) self.fixtureErrors=[NSMutableArray array];
    [self.fixtureErrors addObject:@{@"domain":error.domain ?: @"",@"code":@(error.code)}];
}
@end
@interface YMCIRejectingTopology : YMDisplayTopology
@end
@implementation YMCIRejectingTopology
- (BOOL)configureAndVerifyNewDisplay:(CGDirectDisplayID)displayID width:(NSUInteger)width height:(NSUInteger)height hiDPI:(BOOL)hiDPI baseline:(YMDisplayTopologySnapshot *)baseline error:(NSError **)error {
    if (![super configureAndVerifyNewDisplay:displayID width:width height:height hiDPI:hiDPI baseline:baseline error:error]) return NO;
    if (error) *error=[NSError errorWithDomain:@"DisposableCIInjectedFailure" code:901 userInfo:nil];
    return NO;
}
@end
id YMCIController(YMDisplayTopology *topology) {
    YMCIHostedController *controller=[YMCIHostedController new];
    controller.displayTopology=topology;
    controller.displayProfiles=[NSMutableArray array];
    return controller;
}
id YMCIControllerAddProfile(id opaque, VDVirtualDisplay *display, BOOL hiDPI) {
    YMCIHostedController *controller=opaque;
    YMManagedDisplay *profile=[YMManagedDisplay new];
    profile.width=1920; profile.height=1080; profile.hiDPI=hiDPI;
    profile.ordinal=controller.displayProfiles.count+1; profile.friendlyName=@"Disposable CI";
    profile.display=display;
    [controller.displayProfiles addObject:profile];
    [controller selectProfile:profile];
    return profile;
}
YMDisplayTopology *YMCIRejectingTopologyCreate(void) { return [YMCIRejectingTopology new]; }
