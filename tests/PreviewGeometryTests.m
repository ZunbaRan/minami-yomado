#import "../native/PreviewGeometry.h"

int main(void) {
    @autoreleasepool {
        CGRect usable = CGRectMake(0, 33, 1512, 900);
        NSDictionary *defaults = YMPreviewOpeningOptions(@{}, nil, usable);
        NSCAssert([defaults[@"width"] intValue] == 480 && [defaults[@"height"] intValue] == 300, @"First preview must be compact");
        NSDictionary *requested = @{@"width":@1450, @"height":@760, @"fps":@15};
        NSDictionary *saved = @{@"x":@1000, @"y":@50, @"width":@400, @"height":@260};
        NSDictionary *reopened = YMPreviewOpeningOptions(requested, saved, usable);
        NSCAssert([reopened[@"width"] intValue] == 400 && [reopened[@"height"] intValue] == 260, @"Stale open arguments must not override user size");
        NSCAssert([reopened[@"x"] intValue] == 1000 && [reopened[@"y"] intValue] == 50, @"Remember user position");
        NSCAssert([reopened[@"fps"] intValue] == 15, @"Geometry must not override capture settings");
        NSCAssert([YMPreviewOpeningOptions(requested,nil,usable)[@"width"] intValue] == 1450, @"First-open explicit dimensions remain supported");
        NSDictionary *smaller = YMPreviewOpeningOptions(requested, saved, CGRectMake(0, 33, 640, 480));
        NSCAssert([smaller[@"x"] intValue] == 240 && [smaller[@"y"] intValue] == 50, @"Clamp position after physical display change");
        NSDictionary *large = @{@"x":@-500,@"y":@-100,@"width":@2000,@"height":@1500};
        NSDictionary *clamped = YMPreviewOpeningOptions(@{},large,usable);
        NSCAssert([clamped[@"width"] intValue] == 1512 && [clamped[@"height"] intValue] == 900 && [clamped[@"x"] intValue] == 0 && [clamped[@"y"] intValue] == 33, @"Remembered frame must fit current usable screen");
        for (id invalid in @[@[], @{}, @{@"x":@0,@"y":@0,@"width":@200,@"height":@300}, @{@"x":@0,@"y":@0,@"width":@"400",@"height":@300}, @{@"x":@(NAN),@"y":@0,@"width":@400,@"height":@300}])
            NSCAssert(!YMPreviewSavedFrame(invalid), @"Ignore malformed saved geometry");
        puts("PASS: compact default, saved-size precedence, position, display changes and corrupt-state fallback.");
    }
    return 0;
}
