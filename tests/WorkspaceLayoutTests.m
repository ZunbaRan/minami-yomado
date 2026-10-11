#import <AppKit/AppKit.h>

// Compile only the presentation component into this fixture. Importing its
// implementation gives the assertions access to the actual nested scroll views
// without exposing test-only API or launching the application controller.
// An override is useful when verifying this regression against an older source.
#ifndef YOMADO_WORKSPACE_VIEW_SOURCE
#define YOMADO_WORKSPACE_VIEW_SOURCE "AppWorkspaceView.m"
#endif
#import YOMADO_WORKSPACE_VIEW_SOURCE

static NSUInteger scenarios;

static NSArray<NSDictionary *> *FixtureRows(NSUInteger count) {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger index = 0; index < count; index++) {
        [rows addObject:@{
            @"appName": [NSString stringWithFormat:@"Example App %lu", (unsigned long)index],
            @"bundleIdentifier": [NSString stringWithFormat:@"example.app.%lu", (unsigned long)index],
            @"windowCount": @1,
            @"pid": @1
        }];
    }
    return rows;
}

static void CheckLayout(NSString *scenario, NSScrollView *board,
                        NSArray<YMAppWorkspaceView *> *tiles) {
    [board.window.contentView layoutSubtreeIfNeeded];
    for (YMAppWorkspaceView *tile in tiles) {
        NSRect screenInDocument = [tile.screenView convertRect:tile.screenView.bounds
                                                       toView:board.documentView];
        // AppKit may round a frame by one point at these proportional widths.
        BOOL correctRatio = fabs(tile.bounds.size.height -
                                 tile.bounds.size.width / tile.displayAspectRatio) <= 1;
        // The board uses an unflipped NSStackView, so its top is maxY.
        BOOL topAligned = fabs(NSMaxY(screenInDocument) -
                               NSMaxY(board.documentView.bounds)) <= 1;
        if (tile.hasAmbiguousLayout || !correctRatio || !topAligned) {
            fprintf(stderr, "FAIL %s: tile=%u ambiguous=%d frame=%s screenInDocument=%s\n",
                    scenario.UTF8String, tile.displayID, tile.hasAmbiguousLayout,
                    NSStringFromRect(tile.frame).UTF8String,
                    NSStringFromRect(screenInDocument).UTF8String);
            exit(1);
        }
    }
    scenarios++;
    printf("PASS %s: 3 proportional tiles, unambiguous, top aligned\n", scenario.UTF8String);
}

int main(void) {
    @autoreleasepool {
        // Requires a macOS WindowServer session. This process never orders a
        // window front, activates itself, enumerates applications, creates a
        // virtual display, captures the desktop, or sends keyboard/mouse input.
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSWindow *window = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 1000, 412)
                      styleMask:NSWindowStyleMaskBorderless
                        backing:NSBackingStoreBuffered defer:YES];
        NSScrollView *board = [[NSScrollView alloc] initWithFrame:NSMakeRect(24, 18, 952, 310)];
        board.hasHorizontalScroller = YES;
        board.hasVerticalScroller = YES;
        board.autohidesScrollers = YES;
        board.drawsBackground = NO;
        [window.contentView addSubview:board];

        NSStackView *cards = [NSStackView new];
        cards.translatesAutoresizingMaskIntoConstraints = NO;
        cards.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        cards.alignment = NSLayoutAttributeTop;
        cards.distribution = NSStackViewDistributionFill;
        cards.spacing = 14;
        cards.detachesHiddenViews = YES;
        board.documentView = cards;
        NSLayoutConstraint *preferredWidth = [cards.widthAnchor constraintEqualToAnchor:board.contentView.widthAnchor];
        preferredWidth.priority = NSLayoutPriorityDefaultHigh;
        preferredWidth.active = YES;
        [NSLayoutConstraint activateConstraints:@[
            [cards.leadingAnchor constraintEqualToAnchor:board.contentView.leadingAnchor],
            [cards.topAnchor constraintEqualToAnchor:board.contentView.topAnchor],
            [cards.widthAnchor constraintGreaterThanOrEqualToAnchor:board.contentView.widthAnchor],
            [cards.heightAnchor constraintGreaterThanOrEqualToAnchor:board.contentView.heightAnchor]
        ]];

        NSMutableArray<YMAppWorkspaceView *> *tiles = [NSMutableArray array];
        for (NSUInteger index = 0; index < 3; index++) {
            YMAppWorkspaceView *tile = [YMAppWorkspaceView new];
            tile.displayID = (uint32_t)(index + 1);
            tile.physicalDisplay = index < 2;
            tile.displayName = [NSString stringWithFormat:@"Screen %lu", (unsigned long)index + 1];
            tile.displayAspectRatio = 16.0 / 9.0;
            [cards addArrangedSubview:tile];
            CGFloat fraction = (index < 2 ? 2560.0 : 1920.0) / 7040.0;
            [tile.widthAnchor constraintEqualToAnchor:cards.widthAnchor
                                           multiplier:fraction constant:-28 * fraction].active = YES;
            [tile updateRows:FixtureRows(index == 1 ? 18 : 0)
                virtualDisplayAvailable:YES accessibilityTrusted:YES];
            [tiles addObject:tile];
        }
        CheckLayout(@"initial", board, tiles);

        YMAppWorkspaceView *middle = tiles[1];
        NSRect visible = [middle.grid convertRect:middle.desktopScroll.contentView.bounds
                                         fromView:middle.desktopScroll.contentView];
        [middle.grid scrollRectToVisible:NSOffsetRect(visible, 0, -12)];
        CheckLayout(@"grid scroll up", board, tiles);
        [middle.grid scrollRectToVisible:NSOffsetRect(visible, 0, 12)];
        CheckLayout(@"grid scroll down", board, tiles);

        [middle updateRows:FixtureRows(5) virtualDisplayAvailable:YES accessibilityTrusted:YES];
        [tiles[2] updateRows:FixtureRows(1) virtualDisplayAvailable:YES accessibilityTrusted:YES];
        CheckLayout(@"after transfer rows", board, tiles);
        for (NSUInteger refresh = 0; refresh < 40; refresh++) {
            for (YMAppWorkspaceView *tile in tiles) {
                tile.displayName = tile.displayName;
                tile.displayDetail = @"2560 × 1440";
                tile.statusText = @"";
                [tile updateRows:tile.rows virtualDisplayAvailable:YES accessibilityTrusted:YES];
            }
            [window.contentView layoutSubtreeIfNeeded];
        }
        CheckLayout(@"after repeated update", board, tiles);

        for (NSUInteger step = 0; step < 10; step++) {
            NSRect boardVisible = [cards convertRect:board.contentView.bounds fromView:board.contentView];
            [cards scrollRectToVisible:NSOffsetRect(boardVisible, 0, 12)];
        }
        CheckLayout(@"outer scroll 120", board, tiles);
        for (NSUInteger pass = 0; pass < 5; pass++) {
            for (YMAppWorkspaceView *tile in tiles) [tile exerciseAmbiguityInLayout];
            CheckLayout([NSString stringWithFormat:@"exercise ambiguity %lu", (unsigned long)pass], board, tiles);
        }
        [board setFrameSize:NSMakeSize(760, 370)];
        CheckLayout(@"resize narrow taller", board, tiles);
        [board setFrameSize:NSMakeSize(1080, 300)];
        CheckLayout(@"resize wide shorter", board, tiles);
        printf("Passed %lu AppKit layout scenarios using a hidden fixture; no real application windows were read or moved.\n",
               (unsigned long)scenarios);
        return 0;
    }
}
