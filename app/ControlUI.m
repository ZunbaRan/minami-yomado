#import "ControlUI.h"

@implementation YMPanelView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5)
                                                       xRadius:14 yRadius:14];
    [NSColor.controlBackgroundColor setFill];
    [shape fill];
    [[NSColor.separatorColor colorWithAlphaComponent:0.18] setStroke];
    shape.lineWidth = 1;
    [shape stroke];
}
@end

@implementation YMStatusPill
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) { _text = @"未启动"; _tint = NSColor.secondaryLabelColor; }
    return self;
}
- (NSSize)intrinsicContentSize {
    NSSize size = [self.text sizeWithAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium]}];
    return NSMakeSize(size.width + 38, 28);
}
- (void)setText:(NSString *)text {
    _text = [text copy];
    [self invalidateIntrinsicContentSize];
    [self setAccessibilityLabel:text];
    self.needsDisplay = YES;
}
- (void)setTint:(NSColor *)tint { _tint = tint; self.needsDisplay = YES; }
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5)
                                                       xRadius:14 yRadius:14];
    [[self.tint colorWithAlphaComponent:0.10] setFill]; [shape fill];
    [self.tint setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(12, NSMidY(self.bounds) - 3, 6, 6)] fill];
    NSDictionary *attributes = @{NSFontAttributeName:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
                                  NSForegroundColorAttributeName:self.tint};
    NSSize size = [self.text sizeWithAttributes:attributes];
    [self.text drawAtPoint:NSMakePoint(25, round((self.bounds.size.height - size.height) / 2)) withAttributes:attributes];
}
@end

static void YMDrawCenteredText(NSString *text, NSRect rect, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    [text drawInRect:rect withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:size weight:weight],
        NSForegroundColorAttributeName:color, NSParagraphStyleAttributeName:style}];
}

@implementation YMTopologyView
- (BOOL)isFlipped { return YES; }
- (void)setSnapshot:(NSArray<NSDictionary *> *)snapshot {
    _snapshot = [snapshot copy];
    NSMutableArray *descriptions = [NSMutableArray array];
    for (NSDictionary *item in snapshot) {
        [descriptions addObject:[NSString stringWithFormat:@"%@，%@ × %@，%@，位置 %@，%@",
            item[@"name"] ?: @"显示器", item[@"logicalWidth"], item[@"logicalHeight"],
            [item[@"isMain"] boolValue] ? @"主屏" : ([item[@"isVirtual"] boolValue] ? @"虚拟屏" : @"实体屏"),
            item[@"x"], item[@"y"]]];
    }
    [self setAccessibilityElement:YES];
    [self setAccessibilityRole:NSAccessibilityImageRole];
    [self setAccessibilityLabel:[descriptions componentsJoinedByString:@"；"]];
    self.needsDisplay = YES;
}
- (void)setOwnedDisplayID:(uint32_t)ownedDisplayID { _ownedDisplayID = ownedDisplayID; self.needsDisplay = YES; }
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect area = NSInsetRect(self.bounds, 12, 12);
    NSMutableArray *visible = [NSMutableArray array];
    NSRect topology = NSZeroRect;
    BOOL hasBounds = NO;
    for (NSDictionary *item in self.snapshot) {
        if (![item[@"isActive"] boolValue]) continue;
        NSRect bounds = NSMakeRect([item[@"x"] doubleValue], [item[@"y"] doubleValue],
                                  [item[@"logicalWidth"] doubleValue], [item[@"logicalHeight"] doubleValue]);
        if (bounds.size.width <= 0 || bounds.size.height <= 0) continue;
        [visible addObject:item];
        topology = hasBounds ? NSUnionRect(topology, bounds) : bounds;
        hasBounds = YES;
    }
    if (!visible.count) {
        YMDrawCenteredText(@"未检测到活动显示器", NSMakeRect(0, NSMidY(self.bounds) - 10, self.bounds.size.width, 24),
                           13, NSFontWeightRegular, NSColor.secondaryLabelColor);
        return;
    }
    CGFloat scale = MIN(area.size.width / topology.size.width, (area.size.height - 34) / topology.size.height);
    CGFloat originX = area.origin.x + (area.size.width - topology.size.width * scale) / 2;
    CGFloat originY = area.origin.y + (area.size.height - 34 - topology.size.height * scale) / 2;
    for (NSDictionary *item in visible) {
        BOOL owned = [item[@"displayID"] unsignedIntValue] == self.ownedDisplayID && self.ownedDisplayID != 0;
        BOOL virtualDisplay = [item[@"isVirtual"] boolValue];
        BOOL main = [item[@"isMain"] boolValue];
        NSColor *accent = owned ? NSColor.controlAccentColor : NSColor.secondaryLabelColor;
        NSRect rect = NSMakeRect(originX + ([item[@"x"] doubleValue] - topology.origin.x) * scale,
            originY + ([item[@"y"] doubleValue] - topology.origin.y) * scale,
            [item[@"logicalWidth"] doubleValue] * scale, [item[@"logicalHeight"] doubleValue] * scale);
        rect = NSInsetRect(rect, 3, 3);
        NSBezierPath *screen = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:7 yRadius:7];
        [[accent colorWithAlphaComponent:owned ? 0.12 : 0.045] setFill]; [screen fill];
        [[accent colorWithAlphaComponent:owned ? 0.75 : 0.36] setStroke];
        screen.lineWidth = owned ? 1.5 : 1;
        if (virtualDisplay) { CGFloat dashes[] = {4, 3}; [screen setLineDash:dashes count:2 phase:0]; }
        [screen stroke];
        // The white bar denotes the actual main screen, not an intended layout.
        if (main) {
            NSRect bar = NSMakeRect(rect.origin.x + 10, rect.origin.y + 8, MAX(8, rect.size.width - 20), 3);
            [accent setFill]; [[NSBezierPath bezierPathWithRoundedRect:bar xRadius:1.5 yRadius:1.5] fill];
        }
        NSString *title = owned ? @"yomado" : (item[@"name"] ?: @"显示器");
        CGFloat centerY = NSMidY(rect) - 17;
        YMDrawCenteredText(title, NSMakeRect(rect.origin.x + 6, centerY, MAX(1, rect.size.width - 12), 21),
                           12, NSFontWeightSemibold, owned ? NSColor.controlAccentColor : NSColor.labelColor);
        NSString *role = main ? @"主屏" : (virtualDisplay ? @"虚拟屏" : @"实体屏");
        YMDrawCenteredText(role, NSMakeRect(rect.origin.x + 6, centerY + 21, MAX(1, rect.size.width - 12), 18),
                           10, NSFontWeightRegular, NSColor.secondaryLabelColor);
        NSString *resolution = [NSString stringWithFormat:@"%@ × %@", item[@"logicalWidth"], item[@"logicalHeight"]];
        YMDrawCenteredText(resolution, NSMakeRect(rect.origin.x - 8, NSMaxY(rect) + 9, rect.size.width + 16, 18),
                           10, NSFontWeightRegular, NSColor.secondaryLabelColor);
    }
}
@end
