//
//  StashNativeCardOrientation.h
//  StashNative
//
//  Orientation helper function declarations.
//

#import <UIKit/UIKit.h>

/// Installs the AppDelegate swizzle on application:supportedInterfaceOrientationsForWindow: via
/// dispatch_once. No-op after the first install.
void stashInstallOrientationSwizzleIfNeeded(void);

/// Attaches the SDK window to the key window's scene.
void stash_attachWindowToKeyWindowScene(UIWindow *cardWindow, UIWindow *keyWindow);

/// Maps a UIInterfaceOrientation to its single-orientation mask.
UIInterfaceOrientationMask stashOrientationMaskForOrientation(UIInterfaceOrientation orientation);
