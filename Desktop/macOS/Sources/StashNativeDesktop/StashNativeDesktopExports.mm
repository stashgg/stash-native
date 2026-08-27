//
//  StashNativeDesktopExports.mm
//  StashNativeDesktop
//
//  C ABI (Desktop/include/StashNativeDesktop.h) over the core. Every call is marshalled to the
//  main queue except the atomic state reads and GetVersion.
//

#import "StashNativeCardPrivate.h"

#include <string>

static void StashRunOnMain(dispatch_block_t block) {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

// Lifetime barriers: the caller relies on the effect once the call returns (a managed domain
// about to unload, a callback about to become invalid), so an off-main call waits.
static void StashRunOnMainSync(dispatch_block_t block) {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

static NSString *StashStringFromC(const char *s) {
    if (s == nullptr) {
        return @"";
    }
    NSString *converted = [NSString stringWithUTF8String:s];
    return converted ?: @"";
}

extern "C" {

void StashNativeDesktop_SetEventCallback(StashNativeDesktopEventCallback callback, void *userData) {
    StashRunOnMainSync(^{
        [[StashDesktopCore sharedInstance] setEventCallback:callback userData:userData];
    });
}

void StashNativeDesktop_SetHostWindow(void *nativeWindowHandle) {
    NSWindow *window = (__bridge NSWindow *)nativeWindowHandle;
    StashRunOnMain(^{
        [StashDesktopCore sharedInstance].explicitHostWindow = [window isKindOfClass:[NSWindow class]] ? window : nil;
    });
}

static void StashOpen(const char *url, const char *configJson, stash::desktop::SurfaceMode mode) {
    NSString *urlString = StashStringFromC(url);
    std::string json = configJson != nullptr ? configJson : "";
    StashRunOnMain(^{
        stash::desktop::SurfaceConfig config = stash::desktop::parseSurfaceConfig(mode, json);
        [[StashDesktopCore sharedInstance] openURL:urlString config:config];
    });
}

void StashNativeDesktop_OpenCard(const char *url, const char *configJson) {
    StashOpen(url, configJson, stash::desktop::SurfaceMode::Card);
}

void StashNativeDesktop_OpenModal(const char *url, const char *configJson) {
    StashOpen(url, configJson, stash::desktop::SurfaceMode::Modal);
}

void StashNativeDesktop_OpenBrowser(const char *url) {
    NSString *urlString = StashStringFromC(url);
    StashRunOnMain(^{
        [[StashDesktopCore sharedInstance] openBrowser:urlString];
    });
}

void StashNativeDesktop_Dismiss(void) {
    StashRunOnMain(^{
        [[StashDesktopCore sharedInstance] dismiss];
    });
}

void StashNativeDesktop_ResetPresentationState(void) {
    StashRunOnMain(^{
        [[StashDesktopCore sharedInstance] resetPresentationState];
    });
}

int StashNativeDesktop_IsCurrentlyPresented(void) {
    return [[StashDesktopCore sharedInstance] isCurrentlyPresented] ? 1 : 0;
}

int StashNativeDesktop_IsPurchaseProcessing(void) {
    return [[StashDesktopCore sharedInstance] isPurchaseProcessing] ? 1 : 0;
}

void StashNativeDesktop_Prewarm(void) {
    StashRunOnMain(^{
        [[StashDesktopCore sharedInstance] prewarm];
    });
}

void StashNativeDesktop_SetInspectableWebViewsEnabled(int enabled) {
    StashRunOnMain(^{
        [StashDesktopCore sharedInstance].inspectableWebViews = enabled != 0;
    });
}

const char *StashNativeDesktop_GetVersion(void) {
    return STASH_NATIVE_DESKTOP_VERSION;
}

void StashNativeDesktop_Shutdown(void) {
    StashRunOnMainSync(^{
        [[StashDesktopCore sharedInstance] shutdown];
    });
}

}  // extern "C"
