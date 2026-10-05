// Typed C++ facade over the Stash Native desktop C ABI for native apps and custom engines on
// Windows: a singleton, a listener with the checkout callbacks, StashNativeCardConfig,
// openCard / openBrowser, dismiss, resetPresentationState, isCurrentlyPresented,
// isPurchaseProcessing, prewarm, shutdown.
//
// Header-only on purpose: nothing STL-typed crosses the DLL boundary, so any MSVC version and
// either CRT can consume StashNativeDesktop.dll. Link the import library (StashNativeDesktop.lib)
// or define STASH_NATIVE_DESKTOP_NO_IMPORT and resolve the exports yourself.
//
// All calls must come from the thread that owns the host window's message loop; listener
// callbacks arrive on that thread after the WebView2 event that produced them has unwound.
#ifndef STASH_NATIVE_CARD_HPP
#define STASH_NATIVE_CARD_HPP

#include <cstdio>
#include <cstdlib>
#include <charconv>
#include <cmath>
#include <cstring>
#include <string>

#include "StashNativeDesktop.h"

namespace stash {

enum class StashNativeCardPresentation { Attached, Window };

struct StashNativeCardConfig {
    // When false the dialog stays open after onPaymentSuccess / onPaymentFailure.
    bool autoClose = true;
    // Optional HTML hex (#RGB, #RRGGBB, #AARRGGBB) for the sheet background; empty for the default theme.
    std::string backgroundColor;
    // Whether the close button, backdrop click, Esc and the standalone window's close control can dismiss the card.
    bool allowDismiss = true;
    // Attached overlays the host window; Window opens a standalone top-level window.
    StashNativeCardPresentation presentation = StashNativeCardPresentation::Attached;
    // Points; 0 = the 480 x 720 default.
    float width = 0;
    float height = 0;
};

class StashNativeCardListener {
public:
    virtual ~StashNativeCardListener() {}
    // order is the string from window.stash_sdk.onPaymentSuccess(order), empty when omitted.
    virtual void onPaymentSuccess(const std::string &order) { (void)order; }
    virtual void onPaymentFailure() {}
    // User dismissed the checkout, or the page called window.close().
    virtual void onDialogDismissed() {}
    virtual void onOptInResponse(const std::string &optInType) { (void)optInType; }
    virtual void onPageLoaded(double loadTimeMs) { (void)loadTimeMs; }
    // The dialog is dismissed before this is called.
    virtual void onNetworkError() {}
    // Checkout closed without onDialogDismissed and the themed URL opened in the system browser.
    virtual void onExternalPayment(const std::string &url) { (void)url; }
    virtual void onPurchaseProcessing() {}
    virtual void onProcessingCompleted() {}
};

namespace detail {

inline std::string jsonEscape(const std::string &text) {
    std::string out;
    for (unsigned char c : text) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", static_cast<unsigned int>(c));
                    out += buf;
                } else {
                    out += static_cast<char>(c);
                }
        }
    }
    return out;
}

// std::to_chars is locale-independent by definition (printf honours LC_NUMERIC, and the parser
// reads JSON, not the process locale); the float overload gives the shortest round-trip form.
inline std::string number(float v) {
    char buf[32];
    std::to_chars_result r = std::to_chars(buf, buf + sizeof(buf), v);
    return r.ec == std::errc() ? std::string(buf, r.ptr) : std::string("0");
}

inline void appendField(std::string &json, const char *key, const std::string &valueText) {
    json += json.size() > 1 ? ",\"" : "\"";
    json += key;
    json += "\":";
    json += valueText;
}

inline void appendBool(std::string &json, const char *key, bool v) {
    appendField(json, key, v ? "true" : "false");
}

// A dimension that is not finite and positive is left out so the parser applies the default size.
inline void appendDimension(std::string &json, const char *key, float v) {
    if (std::isfinite(v) && v > 0) {
        appendField(json, key, number(v));
    }
}

inline std::string cardConfigJson(const StashNativeCardConfig &c) {
    std::string json = "{";
    appendBool(json, "autoClose", c.autoClose);
    appendField(json, "backgroundColor", "\"" + jsonEscape(c.backgroundColor) + "\"");
    appendBool(json, "allowDismiss", c.allowDismiss);
    appendField(json, "presentation",
                c.presentation == StashNativeCardPresentation::Window ? "\"window\"" : "\"attached\"");
    appendDimension(json, "width", c.width);
    appendDimension(json, "height", c.height);
    json += "}";
    return json;
}

// Maps an ABI event onto the listener. Diagnostics (navigation, navigationBlocked,
// webProcessCrashed, error) have no listener method.
inline void dispatchEvent(StashNativeCardListener *listener, const char *type, const char *payload) {
    if (listener == nullptr || type == nullptr) {
        return;
    }
    std::string value = payload != nullptr ? payload : "";
    if (std::strcmp(type, STASH_NATIVE_DESKTOP_EVENT_PAYMENT_SUCCESS) == 0) {
        listener->onPaymentSuccess(value);
    } else if (std::strcmp(type, STASH_NATIVE_DESKTOP_EVENT_PAYMENT_FAILURE) == 0) {
        listener->onPaymentFailure();
    } else if (std::strcmp(type, STASH_NATIVE_DESKTOP_EVENT_DIALOG_DISMISSED) == 0) {
        listener->onDialogDismissed();
    } else if (std::strcmp(type, STASH_NATIVE_DESKTOP_EVENT_OPT_IN_RESPONSE) == 0) {
        listener->onOptInResponse(value);
    } else if (std::strcmp(type, STASH_NATIVE_DESKTOP_EVENT_PAGE_LOADED) == 0) {
        listener->onPageLoaded(std::strtod(value.c_str(), nullptr));
    } else if (std::strcmp(type, STASH_NATIVE_DESKTOP_EVENT_NETWORK_ERROR) == 0) {
        listener->onNetworkError();
    } else if (std::strcmp(type, STASH_NATIVE_DESKTOP_EVENT_EXTERNAL_PAYMENT) == 0) {
        listener->onExternalPayment(value);
    } else if (std::strcmp(type, STASH_NATIVE_DESKTOP_EVENT_PURCHASE_PROCESSING) == 0) {
        listener->onPurchaseProcessing();
    } else if (std::strcmp(type, STASH_NATIVE_DESKTOP_EVENT_PROCESSING_COMPLETED) == 0) {
        listener->onProcessingCompleted();
    }
}

}  // namespace detail

// Threading and callback contract: every call goes on the thread that runs the host window's
// message loop (an STA; an MTA thread is refused with an error event). Listener callbacks are
// delivered on that same thread through a posted message, so they arrive after the WebView2
// event that produced them has unwound, never re-entrantly. target=_blank / window.open and
// openLink open the system browser and the checkout stays presented; externalPayment closes it.
// Full guide: docs/windows.md in the stash-native repository.
class StashNativeCard {
public:
    static StashNativeCard &getInstance() {
        static StashNativeCard instance;
        return instance;
    }

    static const char *getVersion() { return StashNativeDesktop_GetVersion(); }

    // Edge DevTools on the checkout webviews. Debug / QA builds only.
    static void setInspectableWebViewsEnabled(bool enabled) {
        StashNativeDesktop_SetInspectableWebViewsEnabled(enabled ? 1 : 0);
    }

    // The listener outlives the presentation; pass nullptr to clear. Replaces any C callback
    // set directly through StashNativeDesktop_SetEventCallback.
    void setListener(StashNativeCardListener *listener) {
        listener_ = listener;
        StashNativeDesktop_SetEventCallback(listener != nullptr ? &StashNativeCard::trampoline : nullptr, this);
    }

    // HWND the card is presented over. Optional: without it the active window of this process is used.
    void setHostWindow(void *hwnd) { StashNativeDesktop_SetHostWindow(hwnd); }

    void openCard(const std::string &url, const StashNativeCardConfig *config = nullptr) {
        std::string json = config != nullptr ? detail::cardConfigJson(*config) : "{}";
        StashNativeDesktop_OpenCard(url.c_str(), json.c_str());
    }

    // The JSON config the game-engine wrappers send (see docs/windows.md): autoClose, allowDismiss,
    // backgroundColor, presentation, width, height and allowFileUrls. Unknown keys are ignored.
    void openCard(const std::string &url, const std::string &configJson) {
        StashNativeDesktop_OpenCard(url.c_str(), configJson.c_str());
    }

    // System browser. There is no browser-closed callback on desktop.
    void openBrowser(const std::string &url) { StashNativeDesktop_OpenBrowser(url.c_str()); }

    // Closes the checkout and invokes onDialogDismissed.
    void dismiss() { StashNativeDesktop_Dismiss(); }

    // Closes the checkout without callbacks.
    void resetPresentationState() { StashNativeDesktop_ResetPresentationState(); }

    bool isCurrentlyPresented() const { return StashNativeDesktop_IsCurrentlyPresented() != 0; }
    bool isPurchaseProcessing() const { return StashNativeDesktop_IsPurchaseProcessing() != 0; }

    // Creates the browser processes ahead of time so the first checkout opens instantly.
    void prewarm() { StashNativeDesktop_Prewarm(); }

    // Releases the WebView2 environment and clears the C callback and with it this listener.
    // Call at exit. To use the SDK again afterwards, call setListener again before the next
    // open: nothing is re-attached implicitly, so a callback the host installs directly through
    // the ABI in the meantime is never replaced.
    void shutdown() {
        StashNativeDesktop_Shutdown();
        listener_ = nullptr;
    }

private:
    StashNativeCard() : listener_(nullptr) {}
    StashNativeCard(const StashNativeCard &) = delete;
    StashNativeCard &operator=(const StashNativeCard &) = delete;

    static void STASH_NATIVE_DESKTOP_CALL trampoline(const char *type, const char *payload, void *userData) {
        StashNativeCard *self = static_cast<StashNativeCard *>(userData);
        if (self != nullptr) {
            detail::dispatchEvent(self->listener_, type, payload);
        }
    }

    StashNativeCardListener *listener_;
};

}  // namespace stash

#endif
