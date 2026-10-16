#import <AppKit/AppKit.h>

@interface Fixture : NSObject
@property(nonatomic) NSMutableArray<NSWindow *> *windows;
@property(nonatomic) NSMutableArray<NSTextField *> *clocks;
@property(nonatomic) NSMutableArray<NSTextField *> *results;
@property(nonatomic) NSMutableArray<NSNumber *> *counts;
- (void)click:(NSButton *)sender;
@end
@implementation Fixture
- (void)click:(NSButton *)sender {
    NSInteger n = [self.counts[sender.tag] integerValue]+1;
    self.counts[sender.tag] = @(n);
    self.results[sender.tag].stringValue = [NSString stringWithFormat:@"Clicks: %ld", (long)n];
}
@end
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        Fixture *fixture = [Fixture new]; fixture.windows = [NSMutableArray array]; fixture.clocks = [NSMutableArray array];
        fixture.results = [NSMutableArray array]; fixture.counts = [NSMutableArray array];
        for (NSInteger i=0; i<2; i++) {
            NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(70+i*550, 200, 520, 360)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                backing:NSBackingStoreBuffered defer:NO];
            window.title = [NSString stringWithFormat:@"Yomado MCP Fixture %ld", (long)i+1]; window.releasedWhenClosed = NO;
            window.backgroundColor = i ? [NSColor colorWithRed:0.25 green:0.12 blue:0.28 alpha:1] : [NSColor colorWithRed:0.08 green:0.20 blue:0.25 alpha:1];
            NSTextField *title = [NSTextField labelWithString:window.title]; title.font = [NSFont boldSystemFontOfSize:26]; title.textColor = NSColor.whiteColor;
            title.frame = NSMakeRect(24, 275, 480, 50); [window.contentView addSubview:title];
            NSButton *button = [NSButton buttonWithTitle:@"Test native click" target:fixture action:@selector(click:)]; button.tag = i;
            button.frame = NSMakeRect(24, 200, 220, 45); [window.contentView addSubview:button];
            NSTextField *result = [NSTextField labelWithString:@"Clicks: 0"]; result.font = [NSFont systemFontOfSize:30]; result.textColor = NSColor.greenColor;
            result.frame = NSMakeRect(24, 115, 450, 55); [window.contentView addSubview:result]; [fixture.results addObject:result]; [fixture.counts addObject:@0];
            NSTextField *clock = [NSTextField labelWithString:@"Live clock"]; clock.font = [NSFont monospacedDigitSystemFontOfSize:24 weight:NSFontWeightRegular]; clock.textColor = NSColor.whiteColor;
            clock.frame = NSMakeRect(24, 40, 450, 55); [window.contentView addSubview:clock]; [fixture.clocks addObject:clock];
            [fixture.windows addObject:window]; [window orderFrontRegardless];
        }
        [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
            (void)timer; for (NSTextField *clock in fixture.clocks) clock.stringValue = [NSDateFormatter localizedStringFromDate:NSDate.date dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
        }];
        [NSApp run];
    }
    return 0;
}
