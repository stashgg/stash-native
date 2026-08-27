// One window: credentials, checkout URL and the three presentation modes, options, and the
// event log. The window is also the host window the card is presented over.

#include "Sample.hpp"

#include <windowsx.h>

#include <cstdio>

#include "StashDesktopJson.h"
#include "StashDesktopUrl.h"

namespace sample {

// -- Strings ---------------------------------------------------------------------------------

std::wstring widen(const std::string &utf8) {
    if (utf8.empty()) {
        return L"";
    }
    int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), nullptr, 0);
    std::wstring out(static_cast<size_t>(len), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), &out[0], len);
    return out;
}

std::string narrow(const std::wstring &utf16) {
    if (utf16.empty()) {
        return "";
    }
    int len = WideCharToMultiByte(CP_UTF8, 0, utf16.c_str(), static_cast<int>(utf16.size()), nullptr, 0, nullptr, nullptr);
    std::string out(static_cast<size_t>(len), '\0');
    WideCharToMultiByte(CP_UTF8, 0, utf16.c_str(), static_cast<int>(utf16.size()), &out[0], len, nullptr, nullptr);
    return out;
}

// -- Settings --------------------------------------------------------------------------------

static const wchar_t *kSettingsKey = L"Software\\Stash\\StashNativeDesktopSample";

static std::string readValue(HKEY key, const wchar_t *name) {
    wchar_t buffer[4096] = L"";
    DWORD size = sizeof(buffer);
    if (RegQueryValueExW(key, name, nullptr, nullptr, reinterpret_cast<LPBYTE>(buffer), &size) != ERROR_SUCCESS) {
        return "";
    }
    return narrow(buffer);
}

static void writeValue(HKEY key, const wchar_t *name, const std::string &value) {
    std::wstring wide = widen(value);
    RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE *>(wide.c_str()),
                   static_cast<DWORD>((wide.size() + 1) * sizeof(wchar_t)));
}

Settings Settings::load() {
    Settings s;
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kSettingsKey, 0, KEY_READ, &key) != ERROR_SUCCESS) {
        return s;
    }
    s.appId = readValue(key, L"appId");
    std::string env = readValue(key, L"environment");
    s.environment = env == "production" ? Environment::Production : env == "staging" ? Environment::Staging : Environment::Test;
    s.lastUrl = readValue(key, L"lastUrl");
    RegCloseKey(key);
    // Earlier builds stored the secret; it is never read back and the value is removed.
    RegDeleteKeyValueW(HKEY_CURRENT_USER, kSettingsKey, L"ingressSecret");
    return s;
}

void Settings::save() const {
    HKEY key = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kSettingsKey, 0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
        return;
    }
    writeValue(key, L"appId", appId);
    writeValue(key, L"environment", environment == Environment::Production ? "production"
                                    : environment == Environment::Staging ? "staging" : "test");
    writeValue(key, L"lastUrl", lastUrl);
    RegCloseKey(key);
}

// -- Event log -------------------------------------------------------------------------------

EventLog &EventLog::shared() {
    static EventLog instance;
    return instance;
}

static void STASH_NATIVE_DESKTOP_CALL onAbiEvent(const char *type, const char *payload, void *) {
    EventEntry entry = {type != nullptr ? type : "", payload != nullptr ? payload : ""};
    EventLog &log = EventLog::shared();
    log.entries_.push_back(entry);
    if (log.onEvent) {
        log.onEvent(entry);
    }
}

void EventLog::install() {
    StashNativeDesktop_SetEventCallback(onAbiEvent, nullptr);
}

std::string urlOrigin(const std::string &url) {
    std::string sch = stash::desktop::url::scheme(url);
    if (sch.empty()) {
        return "";
    }
    return sch + "://" + stash::desktop::url::host(url);
}

std::string EventEntry::summary() const {
    if (type == "pageLoaded" || type == "webProcessCrashed") {
        return type + " " + payload;
    }
    if (type == "navigation") {
        return type + " " + urlOrigin(payload);
    }
    if (type == "navigationBlocked") {
        return type + " " + stash::desktop::json::getString(payload, "reason", "");
    }
    if (payload.empty()) {
        return type;
    }
    return type + " (" + std::to_string(payload.size()) + " bytes)";
}

std::vector<std::string> EventLog::types() const {
    std::vector<std::string> out;
    for (const EventEntry &e : entries_) {
        out.push_back(e.type);
    }
    return out;
}

// -- Window ----------------------------------------------------------------------------------

namespace {

enum ControlId {
    kAppId = 1001,
    kSecret,
    kEnvironment,
    kGenerate,
    kUrl,
    kOpenCard,
    kOpenModal,
    kOpenBrowser,
    kDismiss,
    kLocalPage,
    kMatrixPage,
    kClearLog,
    kAutoClose,
    kAllowDismiss,
    kWindowMode,
    kInspectable,
    kBackground,
    kStatus,
    kLog
};

struct Window {
    HWND hwnd = nullptr;
    HWND controls[32] = {};
    HFONT font = nullptr;
    Settings settings;
    double scale = 1.0;
    // SetWindowText on an edit control sends EN_CHANGE; while the saved values are being
    // restored those notifications must not write half-initialized settings back.
    bool initializing = false;
};

Window g_window;

HWND control(ControlId id) {
    return g_window.controls[id - kAppId];
}

std::string text(ControlId id) {
    wchar_t buffer[4096] = L"";
    GetWindowTextW(control(id), buffer, 4096);
    return narrow(buffer);
}

bool checked(ControlId id) {
    return Button_GetCheck(control(id)) == BST_CHECKED;
}

void setStatus(const std::string &status) {
    SetWindowTextW(control(kStatus), widen(status).c_str());
}

void appendLog(const std::string &line) {
    HWND log = control(kLog);
    int length = GetWindowTextLengthW(log);
    SendMessageW(log, EM_SETSEL, length, length);
    SendMessageW(log, EM_REPLACESEL, FALSE, reinterpret_cast<LPARAM>(widen(line + "\r\n").c_str()));
}

int px(int points) {
    return static_cast<int>(points * g_window.scale);
}

HWND make(const wchar_t *className, const wchar_t *caption, DWORD style, int x, int y, int w, int h, ControlId id, DWORD exStyle = 0) {
    HWND hwnd = CreateWindowExW(exStyle, className, caption, WS_CHILD | WS_VISIBLE | style, px(x), px(y), px(w), px(h),
                                g_window.hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), GetModuleHandleW(nullptr), nullptr);
    SendMessageW(hwnd, WM_SETFONT, reinterpret_cast<WPARAM>(g_window.font), TRUE);
    g_window.controls[id - kAppId] = hwnd;
    return hwnd;
}

void label(const wchar_t *caption, int x, int y) {
    HWND hwnd = CreateWindowExW(0, L"STATIC", caption, WS_CHILD | WS_VISIBLE | SS_RIGHT, px(x), px(y + 3), px(100), px(18),
                                g_window.hwnd, nullptr, GetModuleHandleW(nullptr), nullptr);
    SendMessageW(hwnd, WM_SETFONT, reinterpret_cast<WPARAM>(g_window.font), TRUE);
}

std::string configJson(bool localFiles) {
    std::string json = "{\"autoClose\":" + std::string(checked(kAutoClose) ? "true" : "false") +
                       ",\"allowDismiss\":" + std::string(checked(kAllowDismiss) ? "true" : "false") +
                       ",\"presentation\":\"" + std::string(checked(kWindowMode) ? "window" : "attached") + "\"";
    std::string background = text(kBackground);
    if (!background.empty()) {
        json += ",\"backgroundColor\":\"" + background + "\"";
    }
    if (localFiles) {
        json += ",\"allowFileUrls\":true";
    }
    return json + "}";
}

void saveSettings() {
    g_window.settings.appId = text(kAppId);
    g_window.settings.ingressSecret = text(kSecret);
    int index = ComboBox_GetCurSel(control(kEnvironment));
    g_window.settings.environment = index == 1 ? Environment::Production : index == 2 ? Environment::Staging : Environment::Test;
    g_window.settings.lastUrl = text(kUrl);
    g_window.settings.save();
}

void buildControls() {
    int y = 16;
    label(L"App ID", 16, y);
    make(L"EDIT", L"", WS_BORDER | ES_AUTOHSCROLL, 124, y, 480, 24, kAppId);
    y += 32;
    label(L"Ingress secret", 16, y);
    make(L"EDIT", L"", WS_BORDER | ES_AUTOHSCROLL | ES_PASSWORD, 124, y, 480, 24, kSecret);
    y += 32;
    label(L"Environment", 16, y);
    HWND combo = make(L"COMBOBOX", L"", CBS_DROPDOWNLIST | WS_VSCROLL, 124, y, 300, 200, kEnvironment);
    ComboBox_AddString(combo, widen(environmentTitle(Environment::Test)).c_str());
    ComboBox_AddString(combo, widen(environmentTitle(Environment::Production)).c_str());
    ComboBox_AddString(combo, widen(environmentTitle(Environment::Staging)).c_str());
    make(L"BUTTON", L"Generate Checkout URL", BS_PUSHBUTTON, 432, y, 172, 26, kGenerate);
    y += 36;
    label(L"Checkout URL", 16, y);
    make(L"EDIT", L"", WS_BORDER | ES_AUTOHSCROLL, 124, y, 480, 24, kUrl);
    y += 34;
    make(L"BUTTON", L"Open Card", BS_PUSHBUTTON, 124, y, 110, 26, kOpenCard);
    make(L"BUTTON", L"Open Modal", BS_PUSHBUTTON, 240, y, 110, 26, kOpenModal);
    make(L"BUTTON", L"Open Browser", BS_PUSHBUTTON, 356, y, 110, 26, kOpenBrowser);
    make(L"BUTTON", L"Dismiss", BS_PUSHBUTTON, 472, y, 110, 26, kDismiss);
    y += 32;
    make(L"BUTTON", L"Local Test Page", BS_PUSHBUTTON, 124, y, 140, 26, kLocalPage);
    make(L"BUTTON", L"Validation Matrix", BS_PUSHBUTTON, 270, y, 140, 26, kMatrixPage);
    make(L"BUTTON", L"Clear Log", BS_PUSHBUTTON, 416, y, 110, 26, kClearLog);
    y += 34;
    make(L"BUTTON", L"autoClose", BS_AUTOCHECKBOX, 124, y, 100, 22, kAutoClose);
    make(L"BUTTON", L"allowDismiss (modal)", BS_AUTOCHECKBOX, 230, y, 160, 22, kAllowDismiss);
    make(L"BUTTON", L"Window presentation", BS_AUTOCHECKBOX, 396, y, 150, 22, kWindowMode);
    make(L"BUTTON", L"Inspectable", BS_AUTOCHECKBOX, 550, y, 100, 22, kInspectable);
    Button_SetCheck(control(kAutoClose), BST_CHECKED);
    Button_SetCheck(control(kAllowDismiss), BST_CHECKED);
    y += 30;
    label(L"Background", 16, y);
    make(L"EDIT", L"", WS_BORDER | ES_AUTOHSCROLL, 124, y, 200, 24, kBackground);
    y += 32;
    make(L"STATIC", L"Ready", SS_LEFT, 124, y, 480, 20, kStatus);
    y += 28;
    make(L"EDIT", L"", WS_BORDER | WS_VSCROLL | ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL, 16, y, 640, 300, kLog);

    const Settings &s = g_window.settings;
    SetWindowTextW(control(kAppId), widen(s.appId).c_str());
    SetWindowTextW(control(kSecret), widen(s.ingressSecret).c_str());
    ComboBox_SetCurSel(combo, s.environment == Environment::Production ? 1 : s.environment == Environment::Staging ? 2 : 0);
    SetWindowTextW(control(kUrl), widen(s.lastUrl).c_str());
}

void onCommand(int id, int notification) {
    if (g_window.initializing) {
        return;
    }
    stash::StashNativeCard &card = stash::StashNativeCard::getInstance();
    if ((id == kAppId || id == kSecret || id == kUrl) && notification == EN_CHANGE) {
        saveSettings();
        return;
    }
    if (id == kEnvironment && notification == CBN_SELCHANGE) {
        saveSettings();
        return;
    }
    switch (id) {
        case kGenerate: {
            saveSettings();
            setStatus("Generating URL...");
            std::string url;
            std::string error;
            if (generateCheckoutUrl(g_window.settings, kDefaultCheckoutPayload, url, error)) {
                SetWindowTextW(control(kUrl), widen(url).c_str());
                saveSettings();
                setStatus("URL generated");
            } else {
                setStatus(error);
            }
            break;
        }
        case kOpenCard:
            appendLog("openCard " + configJson(false));
            card.openCard(text(kUrl), configJson(false));
            break;
        case kOpenModal:
            appendLog("openModal " + configJson(false));
            card.openModal(text(kUrl), configJson(false));
            break;
        case kOpenBrowser:
            card.openBrowser(text(kUrl));
            break;
        case kDismiss:
            card.dismiss();
            break;
        case kLocalPage: {
            std::string url = testPageUrl("stash_test_checkout.html");
            appendLog("openCard stash_test_checkout.html");
            card.openCard(url, configJson(true));
            break;
        }
        case kMatrixPage: {
            std::string url = testPageUrl("stash_validation_matrix.html") + "?auto=1";
            appendLog("openCard stash_validation_matrix.html?auto=1");
            card.openCard(url, configJson(true));
            break;
        }
        case kClearLog:
            EventLog::shared().clear();
            SetWindowTextW(control(kLog), L"");
            break;
        case kInspectable:
            stash::StashNativeCard::setInspectableWebViewsEnabled(checked(kInspectable));
            break;
        default:
            break;
    }
}

struct StatusListener : stash::StashNativeCardListener {
    void onPaymentSuccess(const std::string &order) override { setStatus("Payment success: " + (order.empty() ? "(no order)" : order)); }
    void onPaymentFailure() override { setStatus("Payment failed"); }
    void onDialogDismissed() override { setStatus("Dismissed"); }
    void onOptInResponse(const std::string &type) override { setStatus("Opt-in: " + type); }
    void onPageLoaded(double ms) override { setStatus("Page loaded in " + std::to_string(static_cast<int>(ms)) + " ms"); }
    void onNetworkError() override { setStatus("Network error"); }
    void onExternalPayment(const std::string &url) override { setStatus("External payment: " + url); }
};

StatusListener g_listener;

LRESULT CALLBACK SampleWindowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_COMMAND:
            onCommand(LOWORD(wParam), HIWORD(wParam));
            return 0;
        case WM_CTLCOLORSTATIC:
            return reinterpret_cast<LRESULT>(GetSysColorBrush(COLOR_WINDOW));
        case WM_CLOSE:
            stash::StashNativeCard::getInstance().shutdown();
            DestroyWindow(hwnd);
            return 0;
        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
        default:
            break;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

}  // namespace

HWND createSampleWindow(HINSTANCE instance) {
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = SampleWindowProc;
    wc.hInstance = instance;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = GetSysColorBrush(COLOR_WINDOW);
    wc.lpszClassName = L"StashNativeDesktopSampleWindow";
    RegisterClassExW(&wc);

    g_window.settings = Settings::load();
    g_window.scale = GetDpiForSystem() / 96.0;
    std::wstring title = L"Stash Native Desktop Sample " + widen(stash::StashNativeCard::getVersion());
    RECT frame = {0, 0, px(676), px(690)};
    AdjustWindowRect(&frame, WS_OVERLAPPEDWINDOW, FALSE);
    g_window.hwnd = CreateWindowExW(0, wc.lpszClassName, title.c_str(), WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN, CW_USEDEFAULT,
                                    CW_USEDEFAULT, frame.right - frame.left, frame.bottom - frame.top, nullptr, nullptr, instance, nullptr);
    NONCLIENTMETRICSW metrics = {};
    metrics.cbSize = sizeof(metrics);
    SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, sizeof(metrics), &metrics, 0);
    g_window.font = CreateFontIndirectW(&metrics.lfMessageFont);
    g_window.initializing = true;
    buildControls();
    g_window.initializing = false;

    // The window is both the UI and the host the card is presented over.
    stash::StashNativeCard &card = stash::StashNativeCard::getInstance();
    card.setHostWindow(g_window.hwnd);
    card.setListener(&g_listener);
    // The listener replaced the ABI callback; the log needs it back, so chain through the log.
    EventLog::shared().install();
    EventLog::shared().onEvent = [](const EventEntry &entry) {
        appendLog("event " + entry.summary());
        stash::detail::dispatchEvent(&g_listener, entry.type.c_str(), entry.payload.c_str());
    };

    ShowWindow(g_window.hwnd, SW_SHOW);
    UpdateWindow(g_window.hwnd);
    return g_window.hwnd;
}

}  // namespace sample
