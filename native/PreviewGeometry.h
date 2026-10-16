#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

// Persist top-left screen coordinates, independently of AppKit's bottom-left origin.
static inline NSDictionary *YMPreviewSavedFrame(id value) {
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    for (NSString *key in @[@"x", @"y", @"width", @"height"]) {
        if (![value[key] isKindOfClass:NSNumber.class] || !isfinite([value[key] doubleValue])) return nil;
    }
    if ([value[@"width"] doubleValue] < 240 || [value[@"height"] doubleValue] < 160) return nil;
    return value;
}

static inline NSDictionary *YMPreviewOpeningOptions(NSDictionary *requested, NSDictionary *saved, CGRect usable) {
    NSMutableDictionary *options = [@{@"width":@480, @"height":@300} mutableCopy];
    [options addEntriesFromDictionary:requested];
    if (YMPreviewSavedFrame(saved)) {
        // User geometry wins over stale open arguments. Explicit changes use configure.
        double w = MIN([saved[@"width"] doubleValue], usable.size.width);
        double h = MIN([saved[@"height"] doubleValue], usable.size.height);
        options[@"width"] = @(w); options[@"height"] = @(h);
        options[@"x"] = @(MAX(CGRectGetMinX(usable), MIN([saved[@"x"] doubleValue], CGRectGetMaxX(usable)-w)));
        options[@"y"] = @(MAX(CGRectGetMinY(usable), MIN([saved[@"y"] doubleValue], CGRectGetMaxY(usable)-h)));
    }
    return options;
}
