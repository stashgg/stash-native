// Typed C++ facade over the Stash Native desktop C ABI for native apps and custom engines on
// Windows. Same surface as the mobile SDKs: a singleton, a listener with the mobile callbacks,
// StashNativeCardConfig / StashNativeModalConfig, openCard / openModal / openBrowser, dismiss,
// resetPresentationState, isCurrentlyPresented, isPurchaseProcessing, prewarm, shutdown.
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
#include <cmath>
#include <cstring>
#include <string>

#include "StashNativeDesktop.h"

namespace stash {

// Ratio fields exist for API parity with mobile and are ignored on desktop (fixed 480 x 720 pt card).
struct StashNativeCardConfig {
    bool forcePortrait = false;
    float cardHeightRatioPortrait = 0.68f;
    float cardWidthRatioLandscape = 0.7f;
    float cardHeightRatioLandscape = 0.9f;
    float tabletWidthRatioPortrait = 0.4f;
    float tabletHeightRatioPortrait = 0.5f;
    float tabletWidthRatioLandscape = 0.3f;
    float tabletHeightRatioLandscape = 0.6f;
    // When false the dialog stays open after onPaymentSuccess / onPaymentFailure.
    bool autoClose = true;
    // Optional HTML hex (#RGB, #RRGGBB, #AARRGGBB) for the sheet background; empty for the default theme.
    std::string backgroundColor;
};

// Ratio fields exist for API parity with mobile and are ignored on desktop (fixed 480 x 600 pt modal).
struct StashNativeModalConfig {
    float phoneWidthRatioPortrait = 0.80f;
    float phoneHeightRatioPortrait = 0.50f;
    float phoneWidthRatioLandscape = 0.50f;
    float phoneHeightRatioLandscape = 0.80f;
    float tabletWidthRatioPortrait = 0.40f;
    float tabletHeightRatioPortrait = 0.30f;
    float tabletWidthRatioLandscape = 0.30f;
    float tabletHeightRatioLandscape = 0.40f;
    // Whether the close button, backdrop click and Esc can dismiss the modal.
    bool allowDismiss = true;
    bool autoClose = true;
    std::string backgroundColor;
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

// Locale-independent: the host may have set a decimal-comma LC_NUMERIC, and the parser reads
// JSON, not the process locale.
inline std::string number(float v) {
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%g", static_cast<double>(v));
    for (char *p = buf; *p != '\0'; p++) {
        if (*p == ',') {
            *p = '.';
        }
    }
    return buf;
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

// A non-finite ratio is left out so the parser applies the mobile default for that key instead
// of the whole config being rejected as malformed JSON.
inline void appendRatio(std::string &json, const char *key, float v) {
    if (std::isfinite(v)) {
        appendField(json, key, number(v));
    }
}

inline std::string cardConfigJson(const StashNativeCardConfig &c) {
    std::string json = "{";
    appendBool(json, "forcePortrait", c.forcePortrait);
    appendRatio(json, "cardHeightRatioPortrait", c.cardHeightRatioPortrait);
    appendRatio(json, "cardWidthRatioLandscape", c.cardWidthRatioLandscape);
    appendRatio(json, "cardHeightRatioLandscape", c.cardHeightRatioLandscape);
    appendRatio(json, "tabletWidthRatioPortrait", c.tabletWidthRatioPortrait);
    appendRatio(json, "tabletHeightRatioPortrait", c.tabletHeightRatioPortrait);
    appendRatio(json, "tabletWidthRatioLandscape", c.tabletWidthRatioLandscape);
    appendRatio(json, "tabletHeightRatioLandscape", c.tabletHeightRatioLandscape);
    appendBool(json, "autoClose", c.autoClose);
    appendField(json, "backgroundColor", "\"" + jsonEscape(c.backgroundColor) + "\"");
    json += "}";
    return json;
}

inline std::string modalConfigJson(const StashNativeModalConfig &c) {
    std::string json = "{";
    appendRatio(json, "phoneWidthRatioPortrait", c.phoneWidthRatioPortrait);
    appendRatio(json, "phoneHeightRatioPortrait", c.phoneHeightRatioPortrait);
    appendRatio(json, "phoneWidthRatioLandscape", c.phoneWidthRatioLandscape);
    appendRatio(json, "phoneHeightRatioLandscape", c.phoneHeightRatioLandscape);
    appendRatio(json, "tabletWidthRatioPortrait", c.tabletWidthRatioPortrait);
    appendRatio(json, "tabletHeightRatioPortrait", c.tabletHeightRatioPortrait);
    appendRatio(json, "tabletWidthRatioLandscape", c.tabletWidthRatioLandscape);
    appendRatio(json, "tabletHeightRatioLandscape", c.tabletHeightRatioLandscape);
    appendBool(json, "allowDismiss", c.allowDismiss);
    json += ",\"autoClose\":" + std::string(c.autoClose ? "true" : "false");
    json += ",\"backgroundColor\":\"" + jsonEscape(c.backgroundColor) + "\"";
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

    // The JSON config the game-engine wrappers send (see docs/windows.md); supports the
    // desktop-only keys presentation, width, height and allowFileUrls.
    void openCard(const std::string &url, const std::string &configJson) {
        StashNativeDesktop_OpenCard(url.c_str(), configJson.c_str());
    }

    void openModal(const std::string &url, const StashNativeModalConfig *config = nullptr) {
        std::string json = config != nullptr ? detail::modalConfigJson(*config) : "{}";
        StashNativeDesktop_OpenModal(url.c_str(), json.c_str());
    }

    void openModal(const std::string &url, const std::string &configJson) {
        StashNativeDesktop_OpenModal(url.c_str(), configJson.c_str());
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

    // Releases the WebView2 environment. Call at exit; the SDK can be used again afterwards.
    void shutdown() { StashNativeDesktop_Shutdown(); }

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
