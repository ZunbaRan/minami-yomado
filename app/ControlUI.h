#import <AppKit/AppKit.h>

// Presentation only: these views never configure or capture a display.
@interface YMPanelView : NSView
@end

@interface YMStatusPill : NSView
@property(nonatomic, copy) NSString *text;
@property(nonatomic, strong) NSColor *tint;
@end

@interface YMTopologyView : NSView
@property(nonatomic, copy) NSArray<NSDictionary *> *snapshot;
@property(nonatomic) uint32_t ownedDisplayID;
@end
