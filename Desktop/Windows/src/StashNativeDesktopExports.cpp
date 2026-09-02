// C ABI (Desktop/include/StashNativeDesktop.h) over the core. Every call must come from the
// thread that owns the host window's message loop; the state reads are atomic.

#include "StashNativeCardPrivate.hpp"

using stash::desktop::win::Core;

extern "C" {

void StashNativeDesktop_SetEventCallback(StashNativeDesktopEventCallback callback, void *userData) {
    Core::instance().setEventCallback(callback, userData);
}

void StashNativeDesktop_SetHostWindow(void *nativeWindowHandle) {
    Core::instance().setHostWindow(static_cast<HWND>(nativeWindowHandle));
}

static void StashOpen(const char *url, const char *configJson, stash::desktop::SurfaceMode mode) {
    std::string urlString = url != nullptr ? url : "";
    std::string json = configJson != nullptr ? configJson : "";
    stash::desktop::SurfaceConfig config = stash::desktop::parseSurfaceConfig(mode, json);
    Core::instance().open(urlString, config);
}

void StashNativeDesktop_OpenCard(const char *url, const char *configJson) {
    StashOpen(url, configJson, stash::desktop::SurfaceMode::Card);
}

void StashNativeDesktop_OpenModal(const char *url, const char *configJson) {
    StashOpen(url, configJson, stash::desktop::SurfaceMode::Modal);
}

void StashNativeDesktop_OpenBrowser(const char *url) {
    Core::instance().openBrowser(url != nullptr ? url : "");
}

void StashNativeDesktop_Dismiss(void) {
    Core::instance().dismiss();
}

void StashNativeDesktop_ResetPresentationState(void) {
    Core::instance().resetPresentationState();
}

int StashNativeDesktop_IsCurrentlyPresented(void) {
    return Core::instance().isCurrentlyPresented() ? 1 : 0;
}

int StashNativeDesktop_IsPurchaseProcessing(void) {
    return Core::instance().isPurchaseProcessing() ? 1 : 0;
}

void StashNativeDesktop_Prewarm(void) {
    Core::instance().prewarm();
}

void StashNativeDesktop_SetInspectableWebViewsEnabled(int enabled) {
    Core::instance().setInspectable(enabled != 0);
}

const char *StashNativeDesktop_GetVersion(void) {
    return STASH_NATIVE_DESKTOP_VERSION;
}

void StashNativeDesktop_Shutdown(void) {
    Core::instance().shutdown();
}

}  // extern "C"
