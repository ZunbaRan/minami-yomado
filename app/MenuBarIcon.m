#import "MenuBarIcon.h"

NSImage *YMMenuBarIcon(void) {
    NSImage *image = [NSImage imageWithSize:NSMakeSize(18, 18)
                                  flipped:NO
                           drawingHandler:^BOOL(NSRect bounds) {
        [NSGraphicsContext saveGraphicsState];
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:bounds.origin.x yBy:bounds.origin.y];
        [transform scaleXBy:bounds.size.width / 18.0 yBy:bounds.size.height / 18.0];
        [transform concat];

        // Trace only the inner silhouette of night-window.png: the rounded
        // upper-left corner, crescent cutout, and softly rounded lower corners.
        // The original app icon and its dark background remain unchanged.
        NSBezierPath *window = [NSBezierPath bezierPath];
        [window moveToPoint:NSMakePoint(7.00, 17.00)];
        [window lineToPoint:NSMakePoint(10.57, 17.00)];
        [window curveToPoint:NSMakePoint(10.26, 13.96)
               controlPoint1:NSMakePoint(9.89, 16.10)
               controlPoint2:NSMakePoint(9.69, 14.97)];
        [window curveToPoint:NSMakePoint(14.12, 13.33)
               controlPoint1:NSMakePoint(11.04, 12.71)
               controlPoint2:NSMakePoint(12.76, 12.40)];
        [window lineToPoint:NSMakePoint(14.12, 2.12)];
        [window curveToPoint:NSMakePoint(12.99, 1.00)
               controlPoint1:NSMakePoint(14.12, 1.50)
               controlPoint2:NSMakePoint(13.61, 1.00)];
        [window lineToPoint:NSMakePoint(5.01, 1.00)];
        [window curveToPoint:NSMakePoint(3.88, 2.12)
               controlPoint1:NSMakePoint(4.39, 1.00)
               controlPoint2:NSMakePoint(3.88, 1.50)];
        [window lineToPoint:NSMakePoint(3.88, 14.00)];
        [window curveToPoint:NSMakePoint(7.00, 17.00)
               controlPoint1:NSMakePoint(3.88, 15.65)
               controlPoint2:NSMakePoint(5.26, 17.00)];
        [window closePath];
        [NSColor.blackColor setFill];
        [window fill];
        [NSGraphicsContext restoreGraphicsState];
        return YES;
    }];
    image.template = YES;
    return image;
}
