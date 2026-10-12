#ifndef YOMADO_MENU_BAR_ICON_H
#define YOMADO_MENU_BAR_ICON_H

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// The existing night-window mark as an 18 pt, resolution-independent template.
// NSStatusBarButton supplies the appropriate light, dark, and selected tint.
FOUNDATION_EXPORT NSImage *YMMenuBarIcon(void);

NS_ASSUME_NONNULL_END

#endif
