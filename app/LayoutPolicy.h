#ifndef YOMADO_LAYOUT_POLICY_H
#define YOMADO_LAYOUT_POLICY_H

#import <Foundation/Foundation.h>
#include <math.h>

// Find the physical desktop's right edge without changing its main display,
// positions, or vertical arrangement. A negative edge is a valid result.
static inline NSNumber *YMPhysicalRightEdge(NSArray *snapshot) {
    if (![snapshot isKindOfClass:[NSArray class]]) return nil;
    NSNumber *rightEdge = nil;
    for (id value in snapshot) {
        if (![value isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *display = value;
        id active = display[@"isActive"];
        id online = display[@"isOnline"];
        id virtualDisplay = display[@"isVirtual"];
        if (![active isKindOfClass:[NSNumber class]] || ![active boolValue] ||
            ![online isKindOfClass:[NSNumber class]] || ![online boolValue] ||
            ![virtualDisplay isKindOfClass:[NSNumber class]] || [virtualDisplay boolValue]) continue;

        id rawX = display[@"x"];
        id rawWidth = display[@"logicalWidth"];
        if (![rawX isKindOfClass:[NSNumber class]] ||
            ![rawWidth isKindOfClass:[NSNumber class]]) continue;
        double x = [rawX doubleValue];
        double width = [rawWidth doubleValue];
        double candidate = x + width;
        if (!isfinite(x) || !isfinite(width) || width <= 0 || !isfinite(candidate)) continue;
        if (rightEdge == nil || candidate > rightEdge.doubleValue) rightEdge = @(candidate);
    }
    return rightEdge;
}

#endif
