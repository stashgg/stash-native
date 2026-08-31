// Windows-side checks: web message parsing, the per-game user data folder, the header-only
// facade (config serialization and listener dispatch) and the ABI version through the DLL.
// The shared contract vectors run in Desktop/shared/tests on every platform.
#include <clocale>
#include <cstdio>
#include <limits>
#include <string>

#include "StashDesktopConfig.h"
#include "StashDesktopJson.h"
#include "StashDesktopWebMessage.hpp"
#include "StashNativeCard.hpp"

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

using namespace stash::desktop::win;

static void testWebMessageParsing() {
    std::string type;
    std::string payload;
    CHECK(parseWebMessage("{\"type\":\"stashPaymentSuccess\",\"data\":\"order-1\"}", type, payload));
    CHECK(type == "stashPaymentSuccess" && payload == "order-1");
    CHECK(parseWebMessage("{\"type\":\"stashPaymentFailure\",\"data\":{\"reason\":\"declined\"}}", type, payload));
    CHECK(type == "stashPaymentFailure" && payload == "{\"reason\":\"declined\"}");
    CHECK(parseWebMessage("{\"type\":\"stashOptin\"}", type, payload));
    CHECK(type == "stashOptin" && payload.empty());
    CHECK(parseWebMessage("{\"type\":\"stashPaymentSuccess\",\"data\":null}", type, payload));
    CHECK(payload.empty());
    // Pre-stringified message: one level of quoting is unwrapped.
    CHECK(parseWebMessage("\"{\\\"type\\\":\\\"stashWindowClose\\\",\\\"data\\\":{}}\"", type, payload));
    CHECK(type == "stashWindowClose" && payload == "{}");
    CHECK(!parseWebMessage("{\"data\":1}", type, payload));
    CHECK(!parseWebMessage("\"just a string\"", type, payload));
    CHECK(!parseWebMessage("", type, payload));
    CHECK(!parseWebMessage("[1,2]", type, payload));
}

static bool hasShape(const std::wstring &folder, const std::wstring &prefix) {
    // <prefix>-<8 hex>\WebView2
    const std::wstring tail = L"\\WebView2";
    if (folder.size() != prefix.size() + 9 + tail.size() || folder.compare(0, prefix.size(), prefix) != 0 ||
        folder[prefix.size()] != L'-' || folder.compare(folder.size() - tail.size(), tail.size(), tail) != 0) {
        return false;
    }
    for (size_t i = prefix.size() + 1; i < prefix.size() + 9; i++) {
        wchar_t c = folder[i];
        if (!((c >= L'0' && c <= L'9') || (c >= L'a' && c <= L'f'))) {
            return false;
        }
    }
    return true;
}

static void testUserDataFolder() {
    std::wstring alpha = userDataFolderFor(L"C:\\Users\\me\\AppData\\Local", L"C:\\Games\\Alpha\\Game.exe");
    std::wstring beta = userDataFolderFor(L"C:\\Users\\me\\AppData\\Local", L"D:\\Games\\Beta\\Game.exe");
    CHECK(hasShape(alpha, L"C:\\Users\\me\\AppData\\Local\\Stash\\game"));
    CHECK(hasShape(beta, L"C:\\Users\\me\\AppData\\Local\\Stash\\game"));
    // Same basename, different installs: different profiles.
    CHECK(alpha != beta);
    // Stable for one install, whatever the path's case or separators, non-ASCII included.
    CHECK(userDataFolderFor(L"C:\\Users\\me\\AppData\\Local", L"c:/games/alpha/game.exe") == alpha);
    CHECK(userDataFolderFor(L"C:\\Users\\me\\AppData\\Local", L"C:\\Games\\\u00C4Game.exe") ==
          userDataFolderFor(L"C:\\Users\\me\\AppData\\Local", L"c:/games/\u00E4game.exe"));
    CHECK(hasShape(userDataFolderFor(L"C:\\Users\\me\\AppData\\Local", L"C:\\Games\\\u00C4Game.exe"),
                   L"C:\\Users\\me\\AppData\\Local\\Stash\\\u00E4game"));
    CHECK(hasShape(userDataFolderFor(L"C:\\Users\\me\\AppData\\Local\\", L"MyGame.exe"),
                   L"C:\\Users\\me\\AppData\\Local\\Stash\\mygame"));
    CHECK(hasShape(userDataFolderFor(L"", L""), L".\\Stash\\game"));
}

struct RecordingListener : stash::StashNativeCardListener {
    std::string last;
    double loadTime = 0;
    void onPaymentSuccess(const std::string &order) override { last = "success:" + order; }
    void onPaymentFailure() override { last = "failure"; }
    void onDialogDismissed() override { last = "dismissed"; }
    void onOptInResponse(const std::string &type) override { last = "optin:" + type; }
    void onPageLoaded(double ms) override { last = "loaded"; loadTime = ms; }
    void onNetworkError() override { last = "network"; }
    void onExternalPayment(const std::string &url) override { last = "external:" + url; }
    void onPurchaseProcessing() override { last = "processing"; }
    void onProcessingCompleted() override { last = "completed"; }
};

static void testFacade() {
    stash::StashNativeCardConfig card;
    card.autoClose = false;
    card.backgroundColor = "#1e1e1e";
    std::string json = stash::detail::cardConfigJson(card);
    CHECK(json.find("\"autoClose\":false") != std::string::npos);
    CHECK(json.find("\"cardHeightRatioPortrait\":0.68") != std::string::npos);
    CHECK(json.find("\"backgroundColor\":\"#1e1e1e\"") != std::string::npos);
    CHECK(json.find("\"forcePortrait\":false") != std::string::npos);

    // A non-finite ratio is omitted (the parser applies its default) instead of producing a
    // malformed object that would reset every other field.
    stash::StashNativeCardConfig nan;
    nan.autoClose = false;
    nan.cardHeightRatioPortrait = std::numeric_limits<float>::quiet_NaN();
    nan.tabletWidthRatioPortrait = std::numeric_limits<float>::infinity();
    std::string nanJson = stash::detail::cardConfigJson(nan);
    CHECK(stash::desktop::json::isObject(nanJson));
    CHECK(nanJson.find("cardHeightRatioPortrait") == std::string::npos);
    CHECK(nanJson.find("tabletWidthRatioPortrait") == std::string::npos);
    CHECK(nanJson.find("\"cardWidthRatioLandscape\":") != std::string::npos);
    stash::desktop::SurfaceConfig parsed = stash::desktop::parseSurfaceConfig(stash::desktop::SurfaceMode::Card, nanJson);
    CHECK(!parsed.autoClose);
    CHECK(parsed.cardHeightRatioPortrait == stash::desktop::SurfaceConfig().cardHeightRatioPortrait);

    // Serialization ignores a decimal-comma process locale.
    if (std::setlocale(LC_NUMERIC, "de-DE") != nullptr) {
        std::string localized = stash::detail::cardConfigJson(card);
        CHECK(localized.find("\"cardHeightRatioPortrait\":0.68") != std::string::npos);
        CHECK(stash::desktop::json::isObject(localized));
        std::setlocale(LC_NUMERIC, "C");
    }

    stash::StashNativeModalConfig modal;
    modal.allowDismiss = false;
    std::string modalJson = stash::detail::modalConfigJson(modal);
    CHECK(modalJson.find("\"allowDismiss\":false") != std::string::npos);
    CHECK(modalJson.find("\"phoneWidthRatioPortrait\":0.8") != std::string::npos);
    CHECK(modalJson.find("\"backgroundColor\":\"\"") != std::string::npos);

    RecordingListener listener;
    stash::detail::dispatchEvent(&listener, STASH_NATIVE_DESKTOP_EVENT_PAYMENT_SUCCESS, "o1");
    CHECK(listener.last == "success:o1");
    stash::detail::dispatchEvent(&listener, STASH_NATIVE_DESKTOP_EVENT_PAGE_LOADED, "123");
    CHECK(listener.last == "loaded" && listener.loadTime == 123.0);
    stash::detail::dispatchEvent(&listener, STASH_NATIVE_DESKTOP_EVENT_EXTERNAL_PAYMENT, "https://x/?theme=dark");
    CHECK(listener.last == "external:https://x/?theme=dark");
    stash::detail::dispatchEvent(&listener, STASH_NATIVE_DESKTOP_EVENT_NAVIGATION, "https://x/");
    CHECK(listener.last == "external:https://x/?theme=dark");
    stash::detail::dispatchEvent(&listener, STASH_NATIVE_DESKTOP_EVENT_PROCESSING_COMPLETED, nullptr);
    CHECK(listener.last == "completed");
    stash::detail::dispatchEvent(nullptr, STASH_NATIVE_DESKTOP_EVENT_PAYMENT_FAILURE, "");
}

static void testAbiThroughDll() {
    std::string version = stash::StashNativeCard::getVersion();
    CHECK(version == STASH_NATIVE_DESKTOP_VERSION);
    stash::StashNativeCard &card = stash::StashNativeCard::getInstance();
    CHECK(!card.isCurrentlyPresented());
    CHECK(!card.isPurchaseProcessing());
    // Safe without a presentation and without a message loop.
    card.dismiss();
    card.resetPresentationState();
    card.openCard("");
    card.openModal("");
    CHECK(!card.isCurrentlyPresented());
    stash::StashNativeCard::setInspectableWebViewsEnabled(true);
    stash::StashNativeCard::setInspectableWebViewsEnabled(false);
}

int main() {
    testWebMessageParsing();
    testUserDataFolder();
    testFacade();
    testAbiThroughDll();
    std::printf("%d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
