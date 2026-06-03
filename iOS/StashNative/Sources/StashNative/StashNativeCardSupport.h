//
//  StashNativeCardSupport.h
//  StashNative
//
//  Pure helpers used across the SDK's translation units: idiom detection, key
//  window / top view controller lookup, interface orientation, system/dark surface colors,
//  corner-radius mask.
//

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

// Compile-time flag for iPad support, default 1. Gates stash_isRunningOniPad.
#ifndef ENABLE_IPAD_SUPPORT
#define ENABLE_IPAD_SUPPORT 1
#endif

/// YES when running on iPad (UIUserInterfaceIdiomPad).
BOOL stash_isRunningOniPad(void);

/// Dark-surface color (#1e1e1e) for the loading overlay and the dark system-background fallback.
UIColor *StashNativeDarkSurfaceColor(void);

/// System background color, or the dark surface color when the active style is dark.
UIColor *stash_getSystemBackgroundColor(void);

/// Corner-rounding mask layer for the given bounds, corners, and radius.
CAShapeLayer *stash_createCornerRadiusMask(CGRect bounds, UIRectCorner corners, CGFloat radius);

/// The app's active key window (scene-aware), or nil.
UIWindow *stash_getKeyWindow(void);

/// Top-most presented view controller (key window root, walking the presentedViewController chain).
UIViewController *stash_getTopPresentedViewController(void);

/// Current interface orientation (scene-aware on iOS 13+).
UIInterfaceOrientation stash_getInterfaceOrientation(void);
