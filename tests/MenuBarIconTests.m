#import <AppKit/AppKit.h>
#import "MenuBarIcon.h"

static void Require(BOOL condition, NSString *message) {
    if (condition) return;
    fprintf(stderr, "FAIL %s\n", message.UTF8String);
    exit(1);
}

static NSBitmapImageRep *Render(NSImage *image, NSInteger scale, NSAppearanceName appearanceName) {
    NSInteger pixels = 18 * scale;
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:pixels pixelsHigh:pixels bitsPerSample:8 samplesPerPixel:4
        hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
        bytesPerRow:0 bitsPerPixel:0];
    [[NSAppearance appearanceNamed:appearanceName] performAsCurrentDrawingAppearance:^{
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        [image drawInRect:NSMakeRect(0, 0, pixels, pixels) fromRect:NSZeroRect
            operation:NSCompositingOperationCopy fraction:1 respectFlipped:NO hints:nil];
        [NSGraphicsContext restoreGraphicsState];
    }];
    return bitmap;
}

int main(void) {
    @autoreleasepool {
        // Image-only rendering: no NSApplication, windows, status items,
        // display capture, real app inventory, or keyboard/mouse input.
        NSImage *icon = YMMenuBarIcon();
        Require(icon.isTemplate, @"AppKit must supply the menu-bar tint");
        Require(NSEqualSizes(icon.size, NSMakeSize(18, 18)), @"18 pt menu-bar canvas");
        for (NSNumber *scaleValue in @[@1, @2]) {
            NSInteger scale = scaleValue.integerValue, pixels = 18 * scale;
            NSData *lightMask = nil;
            for (NSAppearanceName appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
                NSBitmapImageRep *bitmap = Render(icon, scale, appearance);
                NSMutableData *alpha = [NSMutableData dataWithLength:(NSUInteger)(pixels * pixels)];
                uint8_t *mask = alpha.mutableBytes;
                NSUInteger filled = 0;
                for (NSInteger y = 0; y < pixels; y++) {
                    for (NSInteger x = 0; x < pixels; x++) {
                        NSColor *color = [bitmap colorAtX:x y:y];
                        mask[y * pixels + x] = (uint8_t)lround(color.alphaComponent * 255);
                        if (x == 0 || y == 0 || x == pixels - 1 || y == pixels - 1)
                            Require(color.alphaComponent == 0, @"transparent outer margin");
                        if (color.alphaComponent > 0.001) {
                            filled++;
                            Require(color.redComponent < 0.01 && color.greenComponent < 0.01 &&
                                color.blueComponent < 0.01, @"monochrome mask without the app icon background");
                        }
                    }
                }
                Require(filled > (NSUInteger)(pixels * pixels / 4) && filled < (NSUInteger)(pixels * pixels * 2 / 3),
                    @"visible window silhouette with substantial transparent background");
                Require([bitmap colorAtX:9 * scale y:9 * scale].alphaComponent > 0.99, @"solid window body");
                Require([bitmap colorAtX:13 * scale y:2 * scale].alphaComponent == 0, @"transparent crescent cutout");
                if (!lightMask) lightMask = alpha.copy;
                else Require([lightMask isEqualToData:alpha], @"same alpha silhouette in light and dark appearances");
                printf("PASS %s, %ldx: 18 pt template with transparent margins and crescent cutout\n",
                    appearance.UTF8String, (long)scale);
            }
        }
    }
    return 0;
}
