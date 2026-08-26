// One checkout presentation, from open to teardown, as a pure state machine. Both desktop hosts
// drive it: the shim's messages, navigation decisions and user dismiss requests come in, host
// events and surface commands go out through SessionHost. This is where the mobile callback
// contract lives (once-guards, which paths emit dialogDismissed, the purchase-processing lock,
// external-browser handoff), so the two OS cores cannot drift from each other.
#ifndef STASH_DESKTOP_SESSION_H
#define STASH_DESKTOP_SESSION_H

#include <string>

#include "StashDesktopConfig.h"

namespace stash {
namespace desktop {

class SessionHost {
public:
    virtual ~SessionHost() {}
    // Deliver an event to the wrapper / facade. Called synchronously; the host may queue.
    virtual void emitEvent(const std::string &type, const std::string &payload) = 0;
    // Tear the webview UI down (may be deferred, e.g. posted on Windows). Never emits.
    virtual void closeSurface() = 0;
    // http / https in the system browser.
    virtual void openSystemBrowser(const std::string &url) = 0;
    // Non-web scheme handed to the OS; failures are silent.
    virtual void openDeeplinkExternally(const std::string &url) = 0;
    virtual void log(const std::string &message) { (void)message; }
};

enum class NavigationDecision { Load, Cancel };

class Session {
public:
    Session(SessionHost &host, const SurfaceConfig &config, bool systemPrefersDark);

    const SurfaceConfig &config() const { return config_; }
    bool themeIsDark() const { return dark_; }
    std::string themedUrl(const std::string &url) const;

    // Presented until a terminal path runs (auto-close result, dismiss, network error, external
    // payment, reset). Finished sessions ignore every further input.
    bool isPresented() const { return presented_; }
    bool isFinished() const { return finished_; }
    bool isPurchaseProcessing() const { return purchaseProcessing_; }
    bool pageLoadedEmitted() const { return pageLoadedEmitted_; }

    // Shim messages by STASH_SDK_MSG_* name; payload is the coerced string / JSON text.
    void handleMessage(const std::string &name, const std::string &payload);

    void handlePaymentSuccess(const std::string &order);
    void handlePaymentFailure();
    void handlePurchaseProcessing();
    void handleProcessingCompleted();
    void handleOptIn(const std::string &optInType);
    void handleWindowClose();
    void handleExternalPayment(const std::string &rawUrl);
    void handleOpenLink(const std::string &rawUrl);

    // Main-frame policy: deeplinks are consumed (stash-pay results run the bridge flows, other
    // schemes go to the OS silently), file:// needs allowFileUrls, http is blocked, everything
    // else loads and reports a navigation event. A block before the first finished load is a
    // networkError (nothing to show); a block afterwards leaves the loaded page in place.
    NavigationDecision decideMainFrameNavigation(const std::string &url);
    // Sub-frames: deeplinks are consumed the same way, http is blocked, web schemes load.
    NavigationDecision decideSubFrameNavigation(const std::string &url);
    // target=_blank / window.open: external browser, checkout stays open; empty / about:blank dropped.
    void handleNewWindow(const std::string &url);

    // First finished main-frame load of the presentation: pageLoaded once, spinner hides.
    void handlePageFinished(double loadTimeMs);
    // Load failure / deadline / repeated web-process crash: closes without dialogDismissed.
    void handleNetworkError();

    // Close button, backdrop click, Esc, window close button. False when refused (purchase
    // processing, or a modal with allowDismiss = false).
    bool requestUserDismiss();
    // StashNativeDesktop_Dismiss: closes and emits dialogDismissed (mobile dismiss parity).
    void dismiss();
    // StashNativeDesktop_ResetPresentationState: closes with no events.
    void reset();

private:
    void runDeeplinkResult(const std::string &url);
    void finishWithoutDismissEvent();
    void finishWithDismissEvent();
    bool resultOnceGuard();

    SessionHost &host_;
    SurfaceConfig config_;
    bool dark_;
    bool presented_ = true;
    bool finished_ = false;
    bool purchaseProcessing_ = false;
    bool paymentResultHandled_ = false;
    bool dismissEmitted_ = false;
    bool pageLoadedEmitted_ = false;
};

}  // namespace desktop
}  // namespace stash

#endif
