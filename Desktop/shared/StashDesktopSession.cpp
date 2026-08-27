#include "StashDesktopSession.h"

#include <cmath>
#include <cstdio>

#include "../include/StashNativeDesktop.h"
#include "StashDesktopJson.h"
#include "StashDesktopTheme.h"
#include "StashDesktopUrl.h"
#include "StashSdkScript.h"

namespace stash {
namespace desktop {

namespace {

// Scheme policy shared by the main frame and sub-frames: http never loads, file only when the
// wrapper opted in for local test pages.
const char *blockReasonFor(const std::string &u, const SurfaceConfig &config) {
    std::string sch = url::scheme(u);
    if (sch == "file" && !config.allowFileUrls) {
        return "file_urls_disabled";
    }
    if (sch == "http") {
        return "insecure_http";
    }
    return nullptr;
}

}  // namespace

Session::Session(SessionHost &host, const SurfaceConfig &config, bool systemPrefersDark)
    : host_(host), config_(config), dark_(theme::effectiveThemeIsDark(config.backgroundColor, systemPrefersDark)) {}

std::string Session::themedUrl(const std::string &u) const {
    return url::appendThemeQueryParameter(u, dark_);
}

// Bridge payloads cross the C ABI as NUL-terminated strings: an embedded U+0000 (a WebKit
// string message can carry one; WebView2 JSON is decoded the same way) would truncate what the
// integrator sees, so it becomes U+FFFD on every transport.
static std::string withoutEmbeddedNul(const std::string &payload) {
    if (payload.find('\0') == std::string::npos) {
        return payload;
    }
    std::string out;
    out.reserve(payload.size() + 2);
    for (char c : payload) {
        if (c == '\0') {
            out += "\xEF\xBF\xBD";
        } else {
            out += c;
        }
    }
    return out;
}

void Session::handleMessage(const std::string &name, const std::string &rawPayload) {
    std::string payload = withoutEmbeddedNul(rawPayload);
    if (name == STASH_SDK_MSG_PAYMENT_SUCCESS) {
        handlePaymentSuccess(payload);
    } else if (name == STASH_SDK_MSG_PAYMENT_FAILURE) {
        handlePaymentFailure();
    } else if (name == STASH_SDK_MSG_PURCHASE_PROCESSING) {
        handlePurchaseProcessing();
    } else if (name == STASH_SDK_MSG_PROCESSING_COMPLETED) {
        handleProcessingCompleted();
    } else if (name == STASH_SDK_MSG_OPTIN) {
        handleOptIn(payload);
    } else if (name == STASH_SDK_MSG_WINDOW_CLOSE) {
        handleWindowClose();
    } else if (name == STASH_SDK_MSG_EXTERNAL_PAYMENT) {
        handleExternalPayment(payload);
    } else if (name == STASH_SDK_MSG_OPEN_LINK) {
        handleOpenLink(payload);
    } else if (name == STASH_SDK_MSG_EXPAND || name == STASH_SDK_MSG_COLLAPSE) {
        // Defined no-ops on desktop: the card has one size.
    } else {
        host_.log("unknown bridge message: " + name);
    }
}

// With autoClose the first result tears the surface down, so later signals are dropped. With
// autoClose off the page stays alive and may legitimately emit failure then success.
bool Session::resultOnceGuard() {
    if (config_.autoClose && paymentResultHandled_) {
        return false;
    }
    if (config_.autoClose) {
        paymentResultHandled_ = true;
    }
    return true;
}

void Session::handlePaymentSuccess(const std::string &order) {
    if (finished_ || !resultOnceGuard()) {
        return;
    }
    purchaseProcessing_ = false;
    if (config_.autoClose) {
        finishWithoutDismissEvent();
    }
    host_.emitEvent(STASH_NATIVE_DESKTOP_EVENT_PAYMENT_SUCCESS, order);
}

void Session::handlePaymentFailure() {
    if (finished_ || !resultOnceGuard()) {
        return;
    }
    purchaseProcessing_ = false;
    if (config_.autoClose) {
        finishWithoutDismissEvent();
    }
    host_.emitEvent(STASH_NATIVE_DESKTOP_EVENT_PAYMENT_FAILURE, "");
}

void Session::handlePurchaseProcessing() {
    if (finished_) {
        return;
    }
    purchaseProcessing_ = true;
    host_.emitEvent(STASH_NATIVE_DESKTOP_EVENT_PURCHASE_PROCESSING, "");
}

void Session::handleProcessingCompleted() {
    if (finished_) {
        return;
    }
    purchaseProcessing_ = false;
    host_.emitEvent(STASH_NATIVE_DESKTOP_EVENT_PROCESSING_COMPLETED, "");
}

void Session::handleOptIn(const std::string &optInType) {
    if (finished_) {
        return;
    }
    host_.emitEvent(STASH_NATIVE_DESKTOP_EVENT_OPT_IN_RESPONSE, optInType);
    finishWithDismissEvent();
}

// window.close honours the processing lock but not modal allowDismiss, as on mobile.
void Session::handleWindowClose() {
    if (finished_ || purchaseProcessing_) {
        return;
    }
    finishWithDismissEvent();
}

void Session::handleExternalPayment(const std::string &rawUrl) {
    if (finished_) {
        return;
    }
    std::string normalized;
    if (!url::normalizeExternalPaymentUrl(rawUrl, normalized)) {
        // Scheme only: the rejected value may carry signed query data.
        host_.log("openExternalBrowser rejected, scheme " + url::scheme(url::trim(rawUrl)));
        return;
    }
    std::string themed = themedUrl(normalized);
    purchaseProcessing_ = false;
    finishWithoutDismissEvent();
    host_.emitEvent(STASH_NATIVE_DESKTOP_EVENT_EXTERNAL_PAYMENT, themed);
    host_.openSystemBrowser(themed);
}

void Session::handleOpenLink(const std::string &rawUrl) {
    if (finished_) {
        return;
    }
    std::string normalized;
    if (!url::normalizeExternalPaymentUrl(rawUrl, normalized)) {
        // Scheme only: the rejected value may carry signed query data.
        host_.log("openLink rejected, scheme " + url::scheme(url::trim(rawUrl)));
        return;
    }
    host_.openSystemBrowser(normalized);
}

void Session::runDeeplinkResult(const std::string &u) {
    switch (url::classifyDeeplinkResult(u)) {
        case url::DeeplinkResult::Success:
            handlePaymentSuccess("");
            break;
        case url::DeeplinkResult::Failure:
            handlePaymentFailure();
            break;
        case url::DeeplinkResult::Cancel:
            handleWindowClose();
            break;
        case url::DeeplinkResult::None:
            host_.openDeeplinkExternally(u);
            break;
    }
}

NavigationDecision Session::decideMainFrameNavigation(const std::string &raw) {
    if (finished_) {
        return NavigationDecision::Cancel;
    }
    // Normalized once so classification and the scheme policy see the same string.
    std::string u = url::trim(raw);
    if (!url::isWebScheme(u)) {
        runDeeplinkResult(u);
        return NavigationDecision::Cancel;
    }
    const char *blockReason = blockReasonFor(u, config_);
    if (blockReason != nullptr) {
        host_.emitEvent(STASH_NATIVE_DESKTOP_EVENT_NAVIGATION_BLOCKED,
                        json::object({{"url", url::origin(u)}, {"reason", blockReason}}));
        // Before the first load completes there is nothing to fall back to: fail fast instead of
        // spinning until the deadline. Afterwards the loaded page stays.
        if (!pageLoadedEmitted_) {
            handleNetworkError();
        }
        return NavigationDecision::Cancel;
    }
    // Origin only: the URL carries the signed checkout token and wrappers log this event.
    host_.emitEvent(STASH_NATIVE_DESKTOP_EVENT_NAVIGATION, url::origin(u));
    return NavigationDecision::Load;
}

NavigationDecision Session::decideSubFrameNavigation(const std::string &raw) {
    if (finished_) {
        return NavigationDecision::Cancel;
    }
    std::string u = url::trim(raw);
    if (!url::isWebScheme(u)) {
        runDeeplinkResult(u);
        return NavigationDecision::Cancel;
    }
    const char *blockReason = blockReasonFor(u, config_);
    if (blockReason != nullptr) {
        // The parent page stays; only the frame is refused.
        host_.emitEvent(STASH_NATIVE_DESKTOP_EVENT_NAVIGATION_BLOCKED,
                        json::object({{"url", url::origin(u)}, {"reason", blockReason}}));
        return NavigationDecision::Cancel;
    }
    return NavigationDecision::Load;
}

void Session::handleNewWindow(const std::string &raw) {
    std::string u = url::trim(raw);
    if (finished_ || u.empty() || u == "about:blank") {
        return;
    }
    if (url::isWebScheme(u)) {
        std::string normalized;
        if (url::normalizeExternalPaymentUrl(u, normalized)) {
            host_.openSystemBrowser(normalized);
        }
        return;
    }
    // Parity with Android and iOS: a non-web target of a new window goes to the OS as is; the
    // stash-pay result flows are recognized on frame navigations only.
    host_.openDeeplinkExternally(u);
}

void Session::handlePageFinished(double loadTimeMs) {
    if (finished_ || pageLoadedEmitted_) {
        return;
    }
    pageLoadedEmitted_ = true;
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%.0f", loadTimeMs < 0 ? 0.0 : std::floor(loadTimeMs + 0.5));
    host_.emitEvent(STASH_NATIVE_DESKTOP_EVENT_PAGE_LOADED, buf);
}

void Session::handleNetworkError() {
    if (finished_) {
        return;
    }
    finishWithoutDismissEvent();
    host_.emitEvent(STASH_NATIVE_DESKTOP_EVENT_NETWORK_ERROR, "");
}

bool Session::requestUserDismiss() {
    if (finished_) {
        return false;
    }
    if (purchaseProcessing_) {
        return false;
    }
    if (config_.mode == SurfaceMode::Modal && !config_.allowDismiss) {
        return false;
    }
    finishWithDismissEvent();
    return true;
}

void Session::dismiss() {
    if (finished_) {
        return;
    }
    finishWithDismissEvent();
}

void Session::reset() {
    if (finished_) {
        return;
    }
    finishWithoutDismissEvent();
}

// The surface is gone (and isPresented false) before the terminal event reaches the host, so a
// wrapper may open the next checkout from inside the callback.
// Idempotent: a terminal event is delivered synchronously, and an integrator may call Dismiss
// or Reset from inside it. The re-entrant call finishes the session; the outer path then finds
// it finished and closes nothing twice. dismissEmitted_ keeps dialogDismissed to one.
void Session::finishWithoutDismissEvent() {
    if (finished_) {
        return;
    }
    finished_ = true;
    presented_ = false;
    purchaseProcessing_ = false;
    host_.closeSurface();
}

void Session::finishWithDismissEvent() {
    finishWithoutDismissEvent();
    if (!dismissEmitted_) {
        dismissEmitted_ = true;
        host_.emitEvent(STASH_NATIVE_DESKTOP_EVENT_DIALOG_DISMISSED, "");
    }
}

}  // namespace desktop
}  // namespace stash
