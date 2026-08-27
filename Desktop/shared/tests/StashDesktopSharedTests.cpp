// Parity vectors for the shared desktop contract. Plain asserts, no framework; the same vectors
// as the Android JUnit tests (UrlNormalizationTest, ThemeParameterTest, DeeplinkClassificationTest,
// ConfigDefaultsTest, StashBackgroundColorUtilsTest) plus the session flows the mobile
// implementations pin in StashNativeCardInternal.m / StashNativeCardPortraitActivity.java.
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

#include "../../include/StashNativeDesktop.h"
#include "../StashDesktopConfig.h"
#include "../StashDesktopJson.h"
#include "../StashDesktopSession.h"
#include "../StashDesktopTheme.h"
#include "../StashDesktopUrl.h"
#include "../StashSdkScript.h"

using namespace stash::desktop;

static int g_failures = 0;
static int g_checks = 0;

#define CHECK(cond)                                                                       \
    do {                                                                                  \
        g_checks++;                                                                       \
        if (!(cond)) {                                                                    \
            g_failures++;                                                                 \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);                   \
        }                                                                                 \
    } while (0)

#define CHECK_EQ(a, b)                                                                    \
    do {                                                                                  \
        g_checks++;                                                                       \
        if (!((a) == (b))) {                                                              \
            g_failures++;                                                                 \
            std::printf("FAIL %s:%d: %s == %s\n", __FILE__, __LINE__, #a, #b);            \
        }                                                                                 \
    } while (0)

static bool near(double a, double b, double eps = 0.001) {
    return std::fabs(a - b) < eps;
}

static bool contains(const std::string &s, const char *needle) {
    return s.find(needle) != std::string::npos;
}

static int count(const std::string &s, const char *needle) {
    int n = 0;
    size_t pos = 0;
    std::string nd(needle);
    while ((pos = s.find(nd, pos)) != std::string::npos) {
        n++;
        pos += nd.size();
    }
    return n;
}

// -- URL --

static void testUrlNormalization() {
    std::string out;
    CHECK(!url::normalizeExternalPaymentUrl("", out));
    CHECK(!url::normalizeExternalPaymentUrl("   ", out));
    CHECK(!url::normalizeExternalPaymentUrl("javascript:alert(1)", out));
    CHECK(!url::normalizeExternalPaymentUrl("JAVASCRIPT:void(0)", out));
    CHECK(!url::normalizeExternalPaymentUrl("data:text/html,<h1>x</h1>", out));
    CHECK(!url::normalizeExternalPaymentUrl("file:///etc/passwd", out));
    // Mobile parses "https://mailto:a@b.c" as userinfo + host b.c and accepts it; same here.
    CHECK(url::normalizeExternalPaymentUrl("mailto:a@b.c", out) && out == "https://mailto:a@b.c");
    CHECK(!url::normalizeExternalPaymentUrl("https:///nohost", out));
    CHECK(!url::normalizeExternalPaymentUrl("https://ex ample.com/x", out));

    CHECK(url::normalizeExternalPaymentUrl("https://pay.stash.gg/x?y=1", out));
    CHECK_EQ(out, std::string("https://pay.stash.gg/x?y=1"));
    CHECK(url::normalizeExternalPaymentUrl("  pay.stash.gg/checkout  ", out));
    CHECK_EQ(out, std::string("https://pay.stash.gg/checkout"));
    CHECK(url::normalizeExternalPaymentUrl("http://example.com", out));
    CHECK_EQ(out, std::string("http://example.com"));
    CHECK(url::normalizeExternalPaymentUrl("HTTPS://Example.com/Path", out));
    CHECK_EQ(out, std::string("HTTPS://Example.com/Path"));
    // Scheme-less text with a colon still gets https:// (Android/iOS behaviour), host must be valid.
    CHECK(url::normalizeExternalPaymentUrl("localhost:8080/x", out));
    CHECK_EQ(out, std::string("https://localhost:8080/x"));
}

static void testUrlParts() {
    CHECK_EQ(url::scheme("https://a.b/c"), std::string("https"));
    CHECK_EQ(url::scheme("HTTPS://a.b/c"), std::string("https"));
    CHECK_EQ(url::scheme("stashdemo://x"), std::string("stashdemo"));
    CHECK_EQ(url::scheme("/relative/path"), std::string(""));
    CHECK_EQ(url::scheme("no scheme:here"), std::string(""));
    CHECK_EQ(url::host("https://User:pw@Checkout.Stash.gg:443/pay/1?x#y"), std::string("checkout.stash.gg"));
    CHECK_EQ(url::host("https://[::1]:8080/x"), std::string("[::1]"));
    CHECK_EQ(url::host("mailto:a@b"), std::string(""));
}

static void testDeeplinks() {
    CHECK(url::isWebScheme("https://checkout.stash.gg/pay/1"));
    CHECK(url::isWebScheme("http://example.com"));
    CHECK(url::isWebScheme("about:blank"));
    CHECK(url::isWebScheme("javascript:void(0)"));
    CHECK(url::isWebScheme("data:text/html,x"));
    CHECK(url::isWebScheme("blob:https://x/y"));
    CHECK(url::isWebScheme("file:///tmp/x.html"));
    CHECK(url::isWebScheme("/relative"));
    CHECK(!url::isWebScheme("stashdemo://stash-pay/success"));
    CHECK(!url::isWebScheme("market://details?id=x"));
    CHECK(!url::isWebScheme("mailto:a@b.c"));

    CHECK(url::classifyDeeplinkResult("stashdemo://stash-pay/success") == url::DeeplinkResult::Success);
    CHECK(url::classifyDeeplinkResult("myapp://x/STASH-PAY/SUCCESS?y=1") == url::DeeplinkResult::Success);
    CHECK(url::classifyDeeplinkResult("bank://return/stash-pay/failure") == url::DeeplinkResult::Failure);
    CHECK(url::classifyDeeplinkResult("app://stash-pay/cancel") == url::DeeplinkResult::Cancel);
    CHECK(url::classifyDeeplinkResult("stashdemo://misc/passthrough") == url::DeeplinkResult::None);
    CHECK(url::classifyDeeplinkResult("stashdemo://stash-pay/failed") == url::DeeplinkResult::None);
    CHECK(url::classifyDeeplinkResult("") == url::DeeplinkResult::None);
}

static void testThemeParameter() {
    CHECK_EQ(url::appendThemeQueryParameter("", true), std::string(""));
    CHECK_EQ(url::appendThemeQueryParameter("https://pay.stash.gg", true), std::string("https://pay.stash.gg?theme=dark"));
    CHECK_EQ(url::appendThemeQueryParameter("https://pay.stash.gg", false), std::string("https://pay.stash.gg?theme=light"));
    CHECK_EQ(url::appendThemeQueryParameter("https://pay.stash.gg?token=abc", true),
             std::string("https://pay.stash.gg?token=abc&theme=dark"));
    std::string dedup = url::appendThemeQueryParameter("https://pay.stash.gg?theme=light&token=abc", true);
    CHECK_EQ(count(dedup, "theme="), 1);
    CHECK(contains(dedup, "theme=dark"));
    CHECK(!contains(dedup, "theme=light"));
    CHECK(contains(dedup, "token=abc"));
    std::string prefix = url::appendThemeQueryParameter("https://pay.stash.gg?themeX=1", true);
    CHECK(contains(prefix, "themeX=1"));
    CHECK(contains(prefix, "theme=dark"));
    std::string frag = url::appendThemeQueryParameter("https://pay.stash.gg?token=abc#section", true);
    CHECK_EQ(frag, std::string("https://pay.stash.gg?token=abc&theme=dark#section"));
    // Percent-encoded parameters survive untouched (iOS regression: %2B must not become +).
    std::string encoded = url::appendThemeQueryParameter("https://pay.stash.gg/p?sig=a%2Bb%3D&theme=dark", false);
    CHECK_EQ(encoded, std::string("https://pay.stash.gg/p?sig=a%2Bb%3D&theme=light"));
    CHECK_EQ(url::stripThemeQueryParameter("https://x/?theme=dark"), std::string("https://x/"));
    CHECK_EQ(url::stripThemeQueryParameter("https://x/?a=1&theme=dark&b=2#f"), std::string("https://x/?a=1&b=2#f"));

    CHECK(url::isRedirectStatus(301) && url::isRedirectStatus(302) && url::isRedirectStatus(303));
    CHECK(url::isRedirectStatus(307) && url::isRedirectStatus(308));
    CHECK(!url::isRedirectStatus(304) && !url::isRedirectStatus(200) && !url::isRedirectStatus(404));
}

// -- Theme --

static void testColors() {
    uint32_t c = 0;
    CHECK(theme::parseHexColor("#112233", c) && c == 0xFF112233);
    CHECK(theme::parseHexColor("#123", c) && c == 0xFF112233);
    CHECK(theme::parseHexColor("#80112233", c) && c == 0x80112233);
    CHECK(theme::parseHexColor("  #1E1E1E ", c) && c == 0xFF1E1E1E);
    CHECK(theme::parseHexColor("1e1e1e", c) && c == 0xFF1E1E1E);
    CHECK(!theme::parseHexColor("#12345", c));
    CHECK(!theme::parseHexColor("#zzzzzz", c));
    CHECK(!theme::parseHexColor("", c));
    CHECK(!theme::parseHexColor("   ", c));

    CHECK(theme::isDarkColor(0xFF000000));
    CHECK(theme::isDarkColor(0xFF1E1E1E));
    CHECK(!theme::isDarkColor(0xFFFFFFFF));
    CHECK(!theme::isDarkColor(0xFFF7F9F4));

    CHECK(theme::effectiveThemeIsDark("", true));
    CHECK(!theme::effectiveThemeIsDark("", false));
    CHECK(theme::effectiveThemeIsDark("#000000", false));
    CHECK(!theme::effectiveThemeIsDark("#FFFFFF", true));
    CHECK(theme::effectiveThemeIsDark("not-a-color", true));
    CHECK_EQ(theme::sheetBackgroundArgb("", true), theme::kDarkBackgroundArgb);
    CHECK_EQ(theme::sheetBackgroundArgb("", false), theme::kLightBackgroundArgb);
    CHECK_EQ(theme::sheetBackgroundArgb("#123", false), 0xFF112233u);
    CHECK_EQ(theme::cssHex(0x80112233), std::string("#112233"));
    std::string script = theme::darkSheetScript(0xFF1E1E1E);
    CHECK(contains(script, "var BG='#1E1E1E'"));
    CHECK(contains(script, "color-scheme"));
}

// -- JSON --

static void testJson() {
    std::string obj = "{ \"a\": \"x\\\"y\", \"b\": true, \"n\": 1.5, \"o\": {\"k\": [1, 2]}, \"u\": \"\\u00e9\\ud83d\\ude00\" }";
    CHECK(json::isObject(obj));
    CHECK(!json::isObject("[1]"));
    CHECK(!json::isObject(""));
    CHECK(json::isObject(" {} "));
    // Only one complete object counts: truncated, trailing text, trailing comma, bare or missing
    // keys, empty values.
    CHECK(!json::isObject("{\"a\":1"));
    CHECK(!json::isObject("{\"a\":{\"b\":1}"));
    CHECK(!json::isObject("{\"a\":1} x"));
    CHECK(!json::isObject("{\"a\":1,}"));
    CHECK(!json::isObject("{a:1}"));
    CHECK(!json::isObject("{\"a\"}"));
    CHECK(!json::isObject("{\"a\":}"));
    CHECK(!json::isObject("{\"a\":1 \"b\":2}"));
    // Values are validated against the JSON grammar, nested or not: bad literals, malformed
    // numbers, invalid escapes and unbalanced containers all reject the whole object.
    CHECK(!json::isObject("{\"allowFileUrls\":true,\"bad\":tru}"));
    CHECK(!json::isObject("{\"a\":truex}"));
    CHECK(!json::isObject("{\"a\":[1,2}"));
    CHECK(!json::isObject("{\"a\":{\"b\":}}"));
    CHECK(!json::isObject("{\"a\":[1,]}"));
    CHECK(!json::isObject("{\"a\":{\"b\":1,}}"));
    CHECK(!json::isObject("{\"a\":01}"));
    CHECK(!json::isObject("{\"a\":1.}"));
    CHECK(!json::isObject("{\"a\":+1}"));
    CHECK(!json::isObject("{\"a\":1e}"));
    CHECK(!json::isObject("{\"a\":\"\\x\"}"));
    CHECK(!json::isObject("{\"a\":\"\\u12\"}"));
    CHECK(!json::isObject("{\"a\":\"line\nbreak\"}"));
    CHECK(!json::isObject("{\"a\":{\"b\":[\"c\"}}"));
    CHECK(json::isObject("{\"a\":-0.5e+3,\"b\":[true,false,null,{\"c\":[]},[]],\"d\":\"\\/\\u00e9\"}"));
    CHECK(near(json::getNumber("{\"a\":-0.5e+3}", "a", 0), -500));
    CHECK_EQ(json::getString("{\"u\":\"https://x/?a=1\\u0026b=2\\/c\"}", "u", ""), std::string("https://x/?a=1&b=2/c"));
    std::string deep = "{\"a\":";
    for (int k = 0; k < 100; k++) {
        deep += "[";
    }
    CHECK(!json::isObject(deep));
    std::string truncatedRaw;
    CHECK(!json::getRaw("{\"a\":false", "a", truncatedRaw));
    CHECK(json::getBool("{\"a\":false", "a", true));
    CHECK(json::getBool("{\"a\":false,\"b\":1", "a", true));
    CHECK_EQ(json::getString(obj, "a", ""), std::string("x\"y"));
    CHECK(json::getBool(obj, "b", false));
    CHECK(json::getBool(obj, "missing", true));
    CHECK(near(json::getNumber(obj, "n", 0), 1.5));
    CHECK(near(json::getNumber(obj, "a", 7), 7));
    CHECK(near(json::getNumber(obj, "o", 7), 7));
    std::string raw;
    CHECK(json::getRaw(obj, "o", raw) && raw == "{\"k\": [1, 2]}");
    CHECK(!json::getRaw(obj, "zzz", raw));
    CHECK_EQ(json::getString(obj, "u", ""), std::string("\xC3\xA9\xF0\x9F\x98\x80"));
    CHECK(!json::getRaw("{\"a\":", "a", raw));
    CHECK(!json::getRaw("not json", "a", raw));
    CHECK_EQ(json::object({{"url", "https://x/?a=\"1\""}, {"reason", "insecure_http"}}),
             std::string("{\"url\":\"https://x/?a=\\\"1\\\"\",\"reason\":\"insecure_http\"}"));
    CHECK_EQ(json::escape("a\nb\tc\\"), std::string("a\\nb\\tc\\\\"));
    CHECK_EQ(json::dataToPayload("\"order-1\""), std::string("order-1"));
    CHECK_EQ(json::dataToPayload("{\"id\":1}"), std::string("{\"id\":1}"));
    CHECK_EQ(json::dataToPayload(""), std::string(""));
    CHECK_EQ(json::dataToPayload("null"), std::string(""));
}

// -- Config --

static void testConfigDefaults() {
    SurfaceConfig card = parseSurfaceConfig(SurfaceMode::Card, "");
    CHECK(card.mode == SurfaceMode::Card);
    CHECK(card.autoClose);
    CHECK(card.allowDismiss);
    CHECK(!card.forcePortrait);
    CHECK(card.backgroundColor.empty());
    CHECK(card.presentation == Presentation::Attached);
    CHECK(near(card.width, 0) && near(card.height, 0));
    CHECK(!card.allowFileUrls);
    CHECK(near(card.cardHeightRatioPortrait, 0.68));
    CHECK(near(card.cardWidthRatioLandscape, 0.7));
    CHECK(near(card.cardHeightRatioLandscape, 0.9));
    CHECK(near(card.tabletWidthRatioPortrait, 0.4));
    CHECK(near(card.tabletHeightRatioPortrait, 0.5));
    CHECK(near(card.tabletWidthRatioLandscape, 0.3));
    CHECK(near(card.tabletHeightRatioLandscape, 0.6));

    SurfaceConfig modal = parseSurfaceConfig(SurfaceMode::Modal, "{}");
    CHECK(modal.mode == SurfaceMode::Modal);
    CHECK(modal.allowDismiss);
    CHECK(modal.autoClose);
    CHECK(near(modal.phoneWidthRatioPortrait, 0.80));
    CHECK(near(modal.phoneHeightRatioPortrait, 0.50));
    CHECK(near(modal.phoneWidthRatioLandscape, 0.50));
    CHECK(near(modal.phoneHeightRatioLandscape, 0.80));
    CHECK(near(modal.modalTabletWidthRatioPortrait, 0.40));
    CHECK(near(modal.modalTabletHeightRatioPortrait, 0.30));
    CHECK(near(modal.modalTabletWidthRatioLandscape, 0.30));
    CHECK(near(modal.modalTabletHeightRatioLandscape, 0.40));
}

static void testConfigParsing() {
    std::string cardJson =
        "{\"forcePortrait\":true,\"cardHeightRatioPortrait\":5,\"cardWidthRatioLandscape\":0.05,"
        "\"tabletWidthRatioLandscape\":0.55,\"autoClose\":false,\"backgroundColor\":\" #1e1e1e \","
        "\"presentation\":\"window\",\"width\":640,\"height\":-3,\"allowFileUrls\":true,\"unknownKey\":{\"x\":1}}";
    SurfaceConfig card = parseSurfaceConfig(SurfaceMode::Card, cardJson);
    CHECK(card.forcePortrait);
    CHECK(!card.autoClose);
    CHECK(near(card.cardHeightRatioPortrait, 1.0));
    CHECK(near(card.cardWidthRatioLandscape, 0.1));
    CHECK(near(card.tabletWidthRatioLandscape, 0.55));
    CHECK_EQ(card.backgroundColor, std::string("#1e1e1e"));
    CHECK(card.presentation == Presentation::Window);
    CHECK(near(card.width, 640));
    CHECK(near(card.height, 0));
    CHECK(card.allowFileUrls);
    // A card config never carries allowDismiss.
    SurfaceConfig cardNoDismiss = parseSurfaceConfig(SurfaceMode::Card, "{\"allowDismiss\":false}");
    CHECK(cardNoDismiss.allowDismiss);

    SurfaceConfig modal = parseSurfaceConfig(SurfaceMode::Modal,
        "{\"allowDismiss\":false,\"phoneWidthRatioPortrait\":\"wide\",\"tabletHeightRatioPortrait\":0.9,\"autoClose\":true}");
    CHECK(!modal.allowDismiss);
    CHECK(modal.autoClose);
    CHECK(near(modal.phoneWidthRatioPortrait, 0.80));
    CHECK(near(modal.modalTabletHeightRatioPortrait, 0.9));

    // A truncated or garbled config never leaks a partial read: every field takes its default.
    SurfaceConfig malformed = parseSurfaceConfig(SurfaceMode::Card, "{\"autoClose\":false");
    CHECK(malformed.autoClose);
    CHECK(!malformed.allowFileUrls);
    SurfaceConfig malformedFile = parseSurfaceConfig(SurfaceMode::Card, "{\"allowFileUrls\":true,\"autoClose\":false");
    CHECK(!malformedFile.allowFileUrls);
    CHECK(malformedFile.autoClose);
    SurfaceConfig trailing = parseSurfaceConfig(SurfaceMode::Modal, "{\"allowDismiss\":false} extra");
    CHECK(trailing.allowDismiss);
    SurfaceConfig badLiteral = parseSurfaceConfig(SurfaceMode::Card, "{\"allowFileUrls\":true,\"bad\":tru}");
    CHECK(!badLiteral.allowFileUrls);
    SurfaceConfig notObject = parseSurfaceConfig(SurfaceMode::Card, "[1,2]");
    CHECK(notObject.autoClose);

    CHECK(near(clampRatio(0.5), 0.5));
    CHECK(near(clampRatio(0.0), 0.1));
    CHECK(near(clampRatio(-1), 0.1));
    CHECK(near(clampRatio(2), 1.0));
    CHECK(near(clampRatio(std::nan("")), 0.1));
}

static void testSizingRule() {
    SurfaceConfig card = parseSurfaceConfig(SurfaceMode::Card, "{}");
    SurfaceConfig modal = parseSurfaceConfig(SurfaceMode::Modal, "{}");
    SurfaceSize s = resolveSurfaceSize(card, 1920, 1080);
    CHECK(near(s.width, 480) && near(s.height, 720));
    s = resolveSurfaceSize(modal, 1920, 1080);
    CHECK(near(s.width, 480) && near(s.height, 600));
    // Ratios never change the size.
    SurfaceConfig wide = parseSurfaceConfig(SurfaceMode::Card, "{\"tabletWidthRatioLandscape\":1.0,\"tabletHeightRatioLandscape\":1.0}");
    s = resolveSurfaceSize(wide, 3840, 2160);
    CHECK(near(s.width, 480) && near(s.height, 720));
    // Explicit size, raised to the minimum.
    SurfaceConfig explicitSize = parseSurfaceConfig(SurfaceMode::Card, "{\"width\":300,\"height\":900}");
    s = resolveSurfaceSize(explicitSize, 1920, 1080);
    CHECK(near(s.width, 400) && near(s.height, 900));
    // Host clamp: 1280x720 host leaves 672 of height.
    s = resolveSurfaceSize(card, 1280, 720);
    CHECK(near(s.width, 480) && near(s.height, 672));
    // The margin wins over the minimum, down to the absolute floor.
    s = resolveSurfaceSize(card, 420, 300);
    CHECK(near(s.width, 372) && near(s.height, 252));
    s = resolveSurfaceSize(card, 100, 100);
    CHECK(near(s.width, kAbsoluteFloorWidth) && near(s.height, kAbsoluteFloorHeight));
    // Window presentation: no host, no clamp.
    s = resolveSurfaceSize(card, 0, 0);
    CHECK(near(s.width, 480) && near(s.height, 720));
}

// -- Script --

static void testScript() {
    std::string webkit = STASH_SDK_SCRIPT_WEBKIT;
    std::string webview2 = STASH_SDK_SCRIPT_WEBVIEW2;
    const char *functions[] = {"onPaymentSuccess", "onPaymentFailure", "onPurchaseProcessing", "onProcessingCompleted",
                               "setPaymentChannel", "expand", "collapse", "openExternalBrowser", "openLink"};
    for (const char *fn : functions) {
        std::string def = std::string("window.stash_sdk.") + fn + " = function(";
        CHECK_EQ(count(webkit, def.c_str()), 1);
        CHECK_EQ(count(webview2, def.c_str()), 1);
    }
    CHECK_EQ(count(webkit, "window.close = function()"), 1);
    // Exactly the documented function set: 9 stash_sdk functions + window.close.
    CHECK_EQ(count(webkit, "window.stash_sdk."), 9);
    CHECK(contains(webkit, "if (window !== window.top) return;"));
    CHECK(contains(webkit, "window.webkit.messageHandlers[n].postMessage(d)"));
    CHECK(!contains(webkit, "chrome.webview"));
    CHECK(contains(webview2, "window.chrome.webview.postMessage({type:n,data:d})"));
    CHECK(!contains(webview2, "messageHandlers"));
    // Every bridge call is wrapped in try/catch: one try per function + one for window.close (+1 inner).
    CHECK_EQ(count(webkit, "try {"), 11);
    CHECK(contains(webkit, "JSON.stringify(order)"));
    CHECK(contains(webkit, "post('" STASH_SDK_MSG_WINDOW_CLOSE "'"));
    CHECK(contains(webkit, "optinType || ''"));
    CHECK(contains(webkit, "String(url) : ''"));
}

// -- Session --

struct RecordingHost : SessionHost {
    std::vector<std::pair<std::string, std::string>> events;
    std::vector<std::string> browser;
    std::vector<std::string> deeplinks;
    int closes = 0;
    void emitEvent(const std::string &type, const std::string &payload) override { events.push_back({type, payload}); }
    void closeSurface() override { closes++; }
    void openSystemBrowser(const std::string &u) override { browser.push_back(u); }
    void openDeeplinkExternally(const std::string &u) override { deeplinks.push_back(u); }
    bool has(const char *type) const {
        for (auto &e : events) {
            if (e.first == type) {
                return true;
            }
        }
        return false;
    }
    int countType(const char *type) const {
        int n = 0;
        for (auto &e : events) {
            if (e.first == type) {
                n++;
            }
        }
        return n;
    }
};

static SurfaceConfig cardConfig(const char *json = "{}") {
    return parseSurfaceConfig(SurfaceMode::Card, json);
}

static void testSuccessAutoClose() {
    RecordingHost h;
    Session s(h, cardConfig(), false);
    CHECK(s.isPresented());
    s.handleMessage(STASH_SDK_MSG_PAYMENT_SUCCESS, "order-1");
    CHECK_EQ(h.closes, 1);
    CHECK_EQ(h.events.size(), size_t(1));
    CHECK_EQ(h.events[0].first, std::string(STASH_NATIVE_DESKTOP_EVENT_PAYMENT_SUCCESS));
    CHECK_EQ(h.events[0].second, std::string("order-1"));
    CHECK(!s.isPresented());
    CHECK(s.isFinished());
    // Once-guard: duplicates and later signals are dropped, no dialogDismissed.
    s.handlePaymentSuccess("order-2");
    s.handlePaymentFailure();
    s.handleWindowClose();
    CHECK(s.requestUserDismiss() == false);
    s.dismiss();
    CHECK_EQ(h.events.size(), size_t(1));
    CHECK_EQ(h.closes, 1);
}

static void testFailureAutoClose() {
    RecordingHost h;
    Session s(h, cardConfig(), false);
    s.handlePurchaseProcessing();
    CHECK(s.isPurchaseProcessing());
    s.handlePaymentFailure();
    CHECK(!s.isPurchaseProcessing());
    CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_PAYMENT_FAILURE), 1);
    CHECK(!h.has(STASH_NATIVE_DESKTOP_EVENT_DIALOG_DISMISSED));
    CHECK_EQ(h.closes, 1);
    s.handlePaymentSuccess("late");
    CHECK(!h.has(STASH_NATIVE_DESKTOP_EVENT_PAYMENT_SUCCESS));
}

static void testAutoCloseOff() {
    RecordingHost h;
    Session s(h, cardConfig("{\"autoClose\":false}"), false);
    s.handlePaymentFailure();
    CHECK(s.isPresented());
    CHECK_EQ(h.closes, 0);
    // Retry from failure to success is legitimate with autoClose off.
    s.handlePaymentSuccess("{\"id\":1}");
    CHECK(s.isPresented());
    CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_PAYMENT_FAILURE), 1);
    CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_PAYMENT_SUCCESS), 1);
    CHECK_EQ(h.events.back().second, std::string("{\"id\":1}"));
    // The page (or user) closes afterwards: dialogDismissed fires exactly once.
    s.handleWindowClose();
    CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_DIALOG_DISMISSED), 1);
    CHECK_EQ(h.closes, 1);
    s.handleWindowClose();
    s.dismiss();
    CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_DIALOG_DISMISSED), 1);
}

static void testUserDismissPaths() {
    {
        RecordingHost h;
        Session s(h, cardConfig(), false);
        CHECK(s.requestUserDismiss());
        CHECK_EQ(h.closes, 1);
        CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_DIALOG_DISMISSED), 1);
        CHECK(!s.isPresented());
    }
    {
        RecordingHost h;
        Session s(h, cardConfig(), false);
        s.dismiss();
        CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_DIALOG_DISMISSED), 1);
        CHECK_EQ(h.closes, 1);
    }
    {
        RecordingHost h;
        Session s(h, cardConfig(), false);
        s.reset();
        CHECK_EQ(h.closes, 1);
        CHECK(h.events.empty());
        CHECK(!s.isPresented());
    }
    {
        // stash-pay/cancel behaves like window.close.
        RecordingHost h;
        Session s(h, cardConfig(), false);
        CHECK(s.decideMainFrameNavigation("stashdemo://stash-pay/cancel") == NavigationDecision::Cancel);
        CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_DIALOG_DISMISSED), 1);
        CHECK(h.deeplinks.empty());
    }
}

static void testProcessingLock() {
    RecordingHost h;
    Session s(h, cardConfig(), false);
    s.handleMessage(STASH_SDK_MSG_PURCHASE_PROCESSING, "{}");
    CHECK(s.isPurchaseProcessing());
    CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_PURCHASE_PROCESSING), 1);
    CHECK(!s.requestUserDismiss());
    s.handleWindowClose();
    CHECK(s.isPresented());
    CHECK_EQ(h.closes, 0);
    // Programmatic dismiss is not gated by the lock (mobile dismiss()).
    s.handleMessage(STASH_SDK_MSG_PROCESSING_COMPLETED, "{}");
    CHECK(!s.isPurchaseProcessing());
    CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_PROCESSING_COMPLETED), 1);
    CHECK(s.requestUserDismiss());
}

static void testProgrammaticDismissDuringProcessing() {
    RecordingHost h;
    Session s(h, cardConfig(), false);
    s.handlePurchaseProcessing();
    s.dismiss();
    CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_DIALOG_DISMISSED), 1);
    CHECK(!s.isPurchaseProcessing());
}

static void testModalAllowDismiss() {
    RecordingHost h;
    Session s(h, parseSurfaceConfig(SurfaceMode::Modal, "{\"allowDismiss\":false}"), false);
    CHECK(!s.requestUserDismiss());
    CHECK(s.isPresented());
    // window.close still works with allowDismiss off.
    s.handleWindowClose();
    CHECK(!s.isPresented());
    CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_DIALOG_DISMISSED), 1);
}

static void testOptIn() {
    RecordingHost h;
    Session s(h, cardConfig(), false);
    s.handleMessage(STASH_SDK_MSG_OPTIN, "email");
    CHECK_EQ(h.events.size(), size_t(2));
    CHECK_EQ(h.events[0].first, std::string(STASH_NATIVE_DESKTOP_EVENT_OPT_IN_RESPONSE));
    CHECK_EQ(h.events[0].second, std::string("email"));
    CHECK_EQ(h.events[1].first, std::string(STASH_NATIVE_DESKTOP_EVENT_DIALOG_DISMISSED));
    CHECK_EQ(h.closes, 1);
}

static void testExternalPayment() {
    RecordingHost h;
    Session s(h, cardConfig("{\"backgroundColor\":\"#000\"}"), false);
    s.handlePurchaseProcessing();
    s.handleMessage(STASH_SDK_MSG_EXTERNAL_PAYMENT, "pay.example.com/x?a=1");
    CHECK_EQ(h.closes, 1);
    CHECK(!s.isPresented());
    CHECK(!s.isPurchaseProcessing());
    CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_EXTERNAL_PAYMENT), 1);
    CHECK(!h.has(STASH_NATIVE_DESKTOP_EVENT_DIALOG_DISMISSED));
    std::string themed = "https://pay.example.com/x?a=1&theme=dark";
    CHECK_EQ(h.events[1].second, themed);
    CHECK_EQ(h.browser.size(), size_t(1));
    CHECK_EQ(h.browser[0], themed);
}

static void testExternalPaymentRejected() {
    RecordingHost h;
    Session s(h, cardConfig(), false);
    s.handleExternalPayment("javascript:alert(1)");
    s.handleExternalPayment("");
    CHECK(s.isPresented());
    CHECK(h.events.empty());
    CHECK(h.browser.empty());
}

static void testOpenLink() {
    RecordingHost h;
    Session s(h, cardConfig(), true);
    s.handleMessage(STASH_SDK_MSG_OPEN_LINK, "stash.gg/terms");
    CHECK(s.isPresented());
    CHECK(h.events.empty());
    CHECK_EQ(h.closes, 0);
    CHECK_EQ(h.browser.size(), size_t(1));
    // No theme parameter on openLink.
    CHECK_EQ(h.browser[0], std::string("https://stash.gg/terms"));
    s.handleOpenLink("file:///etc/passwd");
    CHECK_EQ(h.browser.size(), size_t(1));
}

static void testNewWindow() {
    RecordingHost h;
    Session s(h, cardConfig(), false);
    s.handleNewWindow("");
    s.handleNewWindow("about:blank");
    CHECK(h.browser.empty() && h.deeplinks.empty());
    s.handleNewWindow("https://www.paypal.com/checkout");
    CHECK_EQ(h.browser.size(), size_t(1));
    CHECK_EQ(h.browser[0], std::string("https://www.paypal.com/checkout"));
    s.handleNewWindow("stashdemo://open");
    CHECK_EQ(h.deeplinks.size(), size_t(1));
    CHECK(s.isPresented());
    CHECK(h.events.empty());
}

static void testNavigationPolicy() {
    {
        RecordingHost h;
        Session s(h, cardConfig(), false);
        CHECK(s.decideMainFrameNavigation("https://checkout.stash.gg/pay/1") == NavigationDecision::Load);
        CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_NAVIGATION), 1);
        // After the first finished load a blocked navigation cancels and the page stays.
        s.handlePageFinished(10);
        CHECK(s.decideMainFrameNavigation("http://insecure.example.com") == NavigationDecision::Cancel);
        CHECK(s.decideMainFrameNavigation("file:///tmp/page.html") == NavigationDecision::Cancel);
        CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_NAVIGATION_BLOCKED), 2);
        CHECK(contains(h.events[2].second, "\"reason\":\"insecure_http\""));
        CHECK(contains(h.events[3].second, "\"reason\":\"file_urls_disabled\""));
        CHECK(s.isPresented());
        CHECK(!h.has(STASH_NATIVE_DESKTOP_EVENT_NETWORK_ERROR));
        // Sub-frames follow the same scheme policy; a refused frame never tears down the page.
        CHECK(s.decideSubFrameNavigation("file:///tmp/frame.html") == NavigationDecision::Cancel);
        CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_NAVIGATION_BLOCKED), 3);
        CHECK(contains(h.events[4].second, "\"reason\":\"file_urls_disabled\""));
        CHECK(s.decideSubFrameNavigation("https://acs.bank.example/challenge") == NavigationDecision::Load);
        CHECK(s.isPresented());
        CHECK(!h.has(STASH_NATIVE_DESKTOP_EVENT_NETWORK_ERROR));
        CHECK(s.decideMainFrameNavigation("about:blank") == NavigationDecision::Load);
        CHECK(s.decideMainFrameNavigation("blob:https://x/y") == NavigationDecision::Load);
        // Other deeplinks: handed to the OS silently, no event, checkout stays open.
        CHECK(s.decideMainFrameNavigation("mailto:help@stash.gg") == NavigationDecision::Cancel);
        CHECK_EQ(h.deeplinks.size(), size_t(1));
        CHECK(s.isPresented());
        CHECK(!h.has(STASH_NATIVE_DESKTOP_EVENT_EXTERNAL_PAYMENT));
        CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_NAVIGATION), 3);
    }
    {
        RecordingHost h;
        Session s(h, cardConfig("{\"allowFileUrls\":true}"), false);
        CHECK(s.decideMainFrameNavigation("file:///tmp/page.html") == NavigationDecision::Load);
        CHECK(s.decideSubFrameNavigation("file:///tmp/frame.html") == NavigationDecision::Load);
        CHECK(s.decideSubFrameNavigation("https://acs.bank.example/challenge") == NavigationDecision::Load);
        CHECK(s.decideSubFrameNavigation("http://acs.bank.example/challenge") == NavigationDecision::Cancel);
        CHECK(s.decideSubFrameNavigation("bankapp://stash-pay/failure") == NavigationDecision::Cancel);
        CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_PAYMENT_FAILURE), 1);
        CHECK(!s.isPresented());
    }
    {
        // A block before the first load completes fails fast: navigationBlocked then networkError.
        RecordingHost h;
        Session s(h, cardConfig(), false);
        CHECK(s.decideMainFrameNavigation("http://checkout.example.com/pay") == NavigationDecision::Cancel);
        CHECK_EQ(h.events.size(), size_t(2));
        CHECK_EQ(h.events[0].first, std::string(STASH_NATIVE_DESKTOP_EVENT_NAVIGATION_BLOCKED));
        CHECK_EQ(h.events[1].first, std::string(STASH_NATIVE_DESKTOP_EVENT_NETWORK_ERROR));
        CHECK(!s.isPresented());
        CHECK_EQ(h.closes, 1);
        RecordingHost h2;
        Session s2(h2, cardConfig(), false);
        CHECK(s2.decideMainFrameNavigation("file:///tmp/page.html") == NavigationDecision::Cancel);
        CHECK(h2.has(STASH_NATIVE_DESKTOP_EVENT_NETWORK_ERROR));
        CHECK(!s2.isPresented());
        // A refused sub-frame before the first load is not a fail-fast: the main document is still coming.
        RecordingHost h3;
        Session s3(h3, cardConfig(), false);
        CHECK(s3.decideSubFrameNavigation("file:///tmp/frame.html") == NavigationDecision::Cancel);
        CHECK(h3.has(STASH_NATIVE_DESKTOP_EVENT_NAVIGATION_BLOCKED));
        CHECK(!h3.has(STASH_NATIVE_DESKTOP_EVENT_NETWORK_ERROR));
        CHECK(s3.isPresented());
        // Surrounding whitespace never slips a URL past the policy: trimmed once, then classified.
        RecordingHost h4;
        Session s4(h4, cardConfig(), false);
        CHECK(s4.decideMainFrameNavigation(" file:///tmp/page.html") == NavigationDecision::Cancel);
        CHECK(contains(h4.events[0].second, "\"url\":\"file:///tmp/page.html\""));
        CHECK(contains(h4.events[0].second, "\"reason\":\"file_urls_disabled\""));
        CHECK(h4.has(STASH_NATIVE_DESKTOP_EVENT_NETWORK_ERROR));
        RecordingHost h5;
        Session s5(h5, cardConfig(), false);
        CHECK(s5.decideSubFrameNavigation("\thttp://acs.bank.example/challenge\n") == NavigationDecision::Cancel);
        CHECK(contains(h5.events[0].second, "\"reason\":\"insecure_http\""));
        CHECK(!h5.has(STASH_NATIVE_DESKTOP_EVENT_NETWORK_ERROR));
        CHECK(s5.isPresented());
        CHECK(s5.decideMainFrameNavigation("  https://checkout.stash.gg/pay/2  ") == NavigationDecision::Load);
        CHECK(contains(h5.events[1].second, "https://checkout.stash.gg/pay/2"));
        CHECK(!contains(h5.events[1].second, " https"));
    }
    {
        // stash-pay/success via deeplink: success with an empty order, once-guarded like the bridge.
        RecordingHost h;
        Session s(h, cardConfig(), false);
        s.decideMainFrameNavigation("stashdemo://stash-pay/success?x=1");
        CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_PAYMENT_SUCCESS), 1);
        CHECK_EQ(h.events[0].second, std::string(""));
        s.decideMainFrameNavigation("stashdemo://stash-pay/success");
        CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_PAYMENT_SUCCESS), 1);
        // Finished sessions cancel everything.
        CHECK(s.decideMainFrameNavigation("https://checkout.stash.gg/") == NavigationDecision::Cancel);
    }
}

static void testPageLoadedAndNetworkError() {
    RecordingHost h;
    Session s(h, cardConfig(), false);
    s.handlePageFinished(123.6);
    s.handlePageFinished(999);
    CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_PAGE_LOADED), 1);
    CHECK_EQ(h.events[0].second, std::string("124"));
    s.handleNetworkError();
    CHECK_EQ(h.closes, 1);
    CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_NETWORK_ERROR), 1);
    CHECK(!h.has(STASH_NATIVE_DESKTOP_EVENT_DIALOG_DISMISSED));
    CHECK(!s.isPresented());
    s.handleNetworkError();
    CHECK_EQ(h.countType(STASH_NATIVE_DESKTOP_EVENT_NETWORK_ERROR), 1);
}

static void testThemedUrl() {
    RecordingHost h;
    Session dark(h, cardConfig(), true);
    CHECK(dark.themeIsDark());
    CHECK_EQ(dark.themedUrl("https://x/?theme=light"), std::string("https://x/?theme=dark"));
    Session light(h, cardConfig("{\"backgroundColor\":\"#FFFFFF\"}"), true);
    CHECK(!light.themeIsDark());
    CHECK_EQ(light.themedUrl("https://x/"), std::string("https://x/?theme=light"));
}

static void testVersion() {
    std::string v = STASH_NATIVE_DESKTOP_VERSION;
    CHECK(!v.empty());
    CHECK(contains(v, "."));
}

int main() {
    testUrlNormalization();
    testUrlParts();
    testDeeplinks();
    testThemeParameter();
    testColors();
    testJson();
    testConfigDefaults();
    testConfigParsing();
    testSizingRule();
    testScript();
    testSuccessAutoClose();
    testFailureAutoClose();
    testAutoCloseOff();
    testUserDismissPaths();
    testProcessingLock();
    testProgrammaticDismissDuringProcessing();
    testModalAllowDismiss();
    testOptIn();
    testExternalPayment();
    testExternalPaymentRejected();
    testOpenLink();
    testNewWindow();
    testNavigationPolicy();
    testPageLoadedAndNetworkError();
    testThemedUrl();
    testVersion();
    std::printf("%d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
