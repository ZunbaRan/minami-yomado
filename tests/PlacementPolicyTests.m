#import <Foundation/Foundation.h>
#import "../native/PlacementPolicy.h"
#import "../app/AppWorkspacePolicy.h"

int main(void) {
    @autoreleasepool {
        CGRect physical = CGRectMake(0,0,1512,982);
        NSCAssert(YMRestorableOrigin(CGRectMake(50,50,520,392), physical), @"Contained window must be admissible");
        NSCAssert(!YMRestorableOrigin(CGRectMake(-100,50,520,392), physical), @"Partly off-screen origin must be rejected before mutation");
        NSCAssert(!YMRestorableOrigin(CGRectMake(1400,50,520,392), physical), @"Two-display spanning origin must be rejected before mutation");
        NSCAssert(!YMRestorableOrigin(CGRectNull, physical), @"Unknown geometry is not recoverable");
        NSCAssert(!YMRestorableOrigin(CGRectZero, physical), @"Empty geometry is not recoverable");
        NSCAssert(YMRestorableOrigin(physical, physical), @"Exact display rectangle can restore");
        NSCAssert(!YMAllowsWindowIdentityFallback(kAXErrorSuccess, 123), @"A known sibling ID cannot enter title/geometry fallback");
        NSCAssert(YMAllowsWindowIdentityFallback(kAXErrorSuccess, 0), @"Unresolved ID can use unique geometry fallback");
        NSCAssert(YMAllowsWindowIdentityFallback(kAXErrorNotImplemented, 0), @"Missing SPI can use unique geometry fallback");
        NSCAssert(!YMWorkspaceVisibleOrdinaryGeometry(@{@"x":@1512,@"y":@0,@"width":@1920,@"height":@30},0,YES,1), @"Menu-bar backing surfaces must not occupy a workspace");
        NSCAssert(YMWorkspaceVisibleOrdinaryGeometry(@{@"x":@1612,@"y":@180,@"width":@520,@"height":@392},0,YES,1), @"Ordinary test windows must count");
        puts("PASS: 11 native placement admission/identity regressions (no display or AX mutations).");
    }
    return 0;
}
