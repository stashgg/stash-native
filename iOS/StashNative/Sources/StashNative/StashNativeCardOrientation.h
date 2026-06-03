//
//  StashNativeCardOrientation.h
//  StashNative
//
//  Orientation helpers that core (the presentation builders) calls. The swizzle install, the
//  scene-attach helper, and the UIDeviceOrientation->mask converter live in
//  StashNativeCardOrientation.m; the swizzle resolver, the public
//  +supportedInterfaceOrientationsForWindow: forwarder, and the StashNativeCardInternal orientation
//  methods (restore / teardown / keyboard lock) are categories there.
//

#import <UIKit/UIKit.h>

/// Installs the one-time AppDelegate swizzle on application:supportedInterfaceOrientationsForWindow:
/// (dispatch_once). Call before presenting a forced-portrait window so the SDK window can rotate to
/// portrait under a landscape-locked host. No-op after the first install.
void stashInstallOrientationSwizzleIfNeeded(void);

/// Attaches a freshly-created SDK window to the key window's scene (iOS 13+ multi-scene safety).
void stash_attachWindowToKeyWindowScene(UIWindow *cardWindow, UIWindow *keyWindow);

/// Maps a UIInterfaceOrientation to its single-orientation mask (used when capturing/restoring the
/// pre-portrait scene orientation).
UIInterfaceOrientationMask stashOrientationMaskForOrientation(UIInterfaceOrientation orientation);
