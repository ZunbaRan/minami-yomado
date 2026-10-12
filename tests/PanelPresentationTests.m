#import "PanelPresentation.h"
#import <math.h>

static NSUInteger scenarios;
static void Check(BOOL condition, const char *message) {
    scenarios++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}

int main(void) {
    @autoreleasepool {
        // Geometry only: no NSApplication, NSWindow, NSScreen enumeration,
        // display bridge call, desktop capture or keyboard/mouse input.
        const YMPanelScreen screens[] = {
            {NSMakeRect(-2560, 0, 2560, 1440), NSMakeRect(-2560, 0, 2560, 1415), NO, NO},
            {NSMakeRect(0, 0, 2560, 1440), NSMakeRect(0, 60, 2560, 1355), NO, YES},
            {NSMakeRect(2560, 0, 1920, 1080), NSMakeRect(2560, 0, 1920, 1055), YES, NO}
        };
        NSRect existing = NSMakeRect(-2100, 300, 1000, 440);
        YMPanelPlacement p = YMControlPanelPlacement(existing, screens, 3, NSMakePoint(300, 400));
        Check(p.screenIndex == 0 && !p.shouldMove && NSEqualRects(p.frame, existing),
              "opening preserves a reachable physical-panel position despite pointer on another screen");

        p = YMControlPanelPlacement(NSMakeRect(3000, 120, 1000, 440), screens, 3, NSMakePoint(-1200, 1430));
        Check(p.screenIndex == 0 && p.shouldMove && NSContainsRect(screens[0].visibleFrame, p.frame),
              "virtual panel returns to physical screen under menu-bar pointer");
        Check(fabs(NSMidX(p.frame) - NSMidX(screens[0].visibleFrame)) < 0.001,
              "virtual-panel recovery centers within chosen physical screen");

        p = YMControlPanelPlacement(NSMakeRect(6000, -3000, 1000, 440), screens, 3, NSMakePoint(2700, 300));
        Check(p.screenIndex == 1 && NSContainsRect(screens[1].visibleFrame, p.frame),
              "offscreen panel and virtual pointer fall back to physical main screen");

        p = YMControlPanelPlacement(NSMakeRect(100, 1300, 1000, 440), screens, 3, NSMakePoint(-300, 500));
        Check(p.screenIndex == 1 && p.frame.origin.x == 100 && NSMaxY(p.frame) == NSMaxY(screens[1].visibleFrame),
              "partially clipped physical panel clamps locally instead of jumping to pointer screen");

        p = YMControlPanelPlacement(NSMakeRect(100, 0, 1000, 440), screens, 3, NSMakePoint(200, 100));
        Check(p.frame.origin.y == 60 && p.frame.origin.x == 100,
              "physical panel clears Dock-excluded visible frame without changing horizontal position");

        p = YMControlPanelPlacement(NSMakeRect(2500, 200, 1000, 440), screens, 3, NSMakePoint(-500, 100));
        Check(p.screenIndex == 0 && NSContainsRect(screens[0].visibleFrame, p.frame),
              "tiny physical overlap does not keep a predominantly virtual panel hidden");

        const YMPanelScreen small[] = {
            {NSMakeRect(0, 0, 640, 480), NSMakeRect(0, 20, 640, 435), NO, YES}
        };
        p = YMControlPanelPlacement(NSMakeRect(5000, 0, 1000, 700), small, 1, NSMakePoint(10, 10));
        Check(NSEqualRects(p.frame, small[0].visibleFrame), "oversized panel fits small physical display");

        const YMPanelScreen vertical[] = {
            {NSMakeRect(0, 1440, 1440, 2560), NSMakeRect(0, 1490, 1440, 2485), NO, NO},
            screens[2]
        };
        p = YMControlPanelPlacement(NSMakeRect(3100, 200, 900, 500), vertical, 2, NSMakePoint(100, 2000));
        Check(p.screenIndex == 0 && NSContainsRect(vertical[0].visibleFrame, p.frame),
              "portrait display above main uses upward AppKit coordinates without Y conversion");

        const YMPanelScreen virtualMain[] = {screens[0], {screens[2].frame, screens[2].visibleFrame, YES, YES}};
        p = YMControlPanelPlacement(NSMakeRect(3000, 0, 1000, 440), virtualMain, 2, NSMakePoint(NAN, NAN));
        Check(p.screenIndex == 0, "virtual main never selected over available physical display");

        p = YMControlPanelPlacement(existing, &screens[2], 1, NSMakePoint(2700, 300));
        Check(p.screenIndex == 0 && p.shouldMove && NSContainsRect(screens[2].visibleFrame, p.frame),
              "headless opening recovers stale physical coordinates into remaining virtual display");

        const YMPanelScreen headless[] = {
            screens[2],
            {NSMakeRect(4480, 0, 1920, 1080), NSMakeRect(4480, 20, 1920, 1035), YES, YES}
        };
        NSRect headlessExisting = NSMakeRect(2800, 200, 1000, 440);
        p = YMControlPanelPlacement(headlessExisting, headless, 2, NSMakePoint(4700, 300));
        Check(p.screenIndex == 0 && !p.shouldMove && NSEqualRects(p.frame, headlessExisting),
              "headless opening preserves an already reachable virtual-screen position");
        p = YMControlPanelPlacement(existing, headless, 2, NSMakePoint(NAN, NAN));
        Check(p.screenIndex == 1 && NSContainsRect(headless[1].visibleFrame, p.frame),
              "headless offscreen recovery falls back to virtual main screen");
        p = YMControlPanelPlacement(existing, headless, 2, NSMakePoint(2700, 1070));
        Check(p.screenIndex == 0 && NSContainsRect(headless[0].visibleFrame, p.frame),
              "headless explicit opening prefers pointer screen including its menu bar");
        const YMPanelScreen unusablePhysical[] = {
            {screens[1].frame, NSZeroRect, NO, YES}, screens[2]
        };
        p = YMControlPanelPlacement(existing, unusablePhysical, 2, NSZeroPoint);
        Check(p.screenIndex == 1 && NSContainsRect(screens[2].visibleFrame, p.frame),
              "unusable physical screen does not block virtual recovery");
        p = YMControlPanelPlacement(existing, NULL, 0, NSZeroPoint);
        Check(p.screenIndex == NSNotFound && !p.shouldMove, "empty display list is a safe no-op");

        const YMPanelScreen invalid[] = {
            {NSMakeRect(0, 0, 100, 100), NSMakeRect(NAN, 0, 100, 100), NO, YES},
            {NSMakeRect(0, 0, 100, 100), NSZeroRect, NO, YES},
            screens[0]
        };
        p = YMControlPanelPlacement(NSMakeRect(NAN, INFINITY, -20, 0), invalid, 3, NSMakePoint(20, 20));
        Check(p.screenIndex == 2 && NSContainsRect(screens[0].visibleFrame, p.frame),
              "invalid frames cannot override a usable physical fallback");

        const YMPanelScreen badVisible[] = {
            {NSMakeRect(0, 0, 100, 100), NSMakeRect(200, 200, 100, 100), NO, YES}
        };
        p = YMControlPanelPlacement(existing, badVisible, 1, NSZeroPoint);
        Check(p.screenIndex == NSNotFound && !p.shouldMove,
              "nonintersecting visible area does not become a target");

        // Repeated explicit opening must converge rather than walking the panel.
        for (NSUInteger index = 0; index < 300; index++) {
            CGFloat x = (CGFloat)((NSInteger)(index * 431 % 13000) - 6500);
            CGFloat y = (CGFloat)((NSInteger)(index * 317 % 6000) - 3000);
            NSRect sample = NSMakeRect(x, y, 100 + index * 13 % 3000, 80 + index * 7 % 1800);
            p = YMControlPanelPlacement(sample, screens, 3, NSMakePoint(-500, 300));
            Check(p.screenIndex != NSNotFound && !screens[p.screenIndex].isVirtual
                && NSContainsRect(screens[p.screenIndex].visibleFrame, p.frame),
                "varied geometry remains entirely within physical visible area");
            YMPanelPlacement second = YMControlPanelPlacement(p.frame, screens, 3, NSMakePoint(800, 300));
            Check(!second.shouldMove && NSEqualRects(second.frame, p.frame),
                "repeated presentation is geometrically idempotent");
        }
        printf("PASS: %lu panel geometry assertions; no GUI or display operations\n", (unsigned long)scenarios);
    }
    return 0;
}
