// Core of the Windows host: session lifetime, event delivery through the message window,
// host-window discovery, presentation selection, prewarm and shutdown.

#include "StashNativeCardPrivate.hpp"

#include <shellapi.h>

#include <cstdarg>
#include <cstdio>

#include "StashDesktopTheme.h"
#include "StashDesktopUrl.h"

namespace stash {
namespace desktop {
namespace win {

// -- Strings and logging --------------------------------------------------------------------

std::wstring widen(const std::string &utf8) {
    if (utf8.empty()) {
        return L"";
    }
    int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), nullptr, 0);
    std::wstring out(static_cast<size_t>(len), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), &out[0], len);
    return out;
}

std::string narrow(const wchar_t *utf16) {
    if (utf16 == nullptr || *utf16 == L'\0') {
        return "";
    }
    int len = WideCharToMultiByte(CP_UTF8, 0, utf16, -1, nullptr, 0, nullptr, nullptr);
    std::string out(len > 0 ? static_cast<size_t>(len - 1) : 0, '\0');
    if (len > 0) {
        WideCharToMultiByte(CP_UTF8, 0, utf16, -1, &out[0], len, nullptr, nullptr);
    }
    return out;
}

// OutputDebugString always; also stderr when STASH_NATIVE_DESKTOP_LOG=stderr (CI, console samples).
static bool logToStderr() {
    static int cached = -1;
    if (cached < 0) {
        wchar_t value[16] = L"";
        DWORD len = GetEnvironmentVariableW(L"STASH_NATIVE_DESKTOP_LOG", value, 16);
        cached = (len > 0 && len < 16 && _wcsicmp(value, L"stderr") == 0) ? 1 : 0;
    }
    return cached == 1;
}

void debugLog(const char *fmt, ...) {
    char buf[1024];
    va_list args;
    va_start(args, fmt);
    _vsnprintf_s(buf, _TRUNCATE, fmt, args);
    va_end(args);
    char line[1100];
    _snprintf_s(line, _TRUNCATE, "[StashNativeDesktop] %s\n", buf);
    OutputDebugStringA(line);
    if (logToStderr()) {
        fputs(line, stderr);
        fflush(stderr);
    }
}

// -- Message window -------------------------------------------------------------------------

static const wchar_t *kMessageWindowClass = L"StashNativeDesktopMessage";

static LRESULT CALLBACK MessageWindowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WMA_EVENT:
            Core::instance().onPostedEvent(reinterpret_cast<std::string *>(lParam));
            return 0;
        case WMA_TEARDOWN:
            Core::instance().onPostedTeardown();
            return 0;
        case WM_TIMER:
            Core::instance().onTimer(static_cast<UINT_PTR>(wParam));
            return 0;
        default:
            break;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

// -- Core -----------------------------------------------------------------------------------

Core &Core::instance() {
    // Never destroyed: the library is never unloaded and WebView2 objects must not die at exit.
    static Core *core = new Core();
    return *core;
}

Core::Core() : presentedMirror_(false), processingMirror_(false) {
    presenter_ = std::make_unique<Presenter>(*this);
}

Core::~Core() {}

HWND Core::messageWindow() {
    if (messageWindow_ != nullptr) {
        return messageWindow_;
    }
    if (module_ == nullptr) {
        module_ = GetModuleHandleW(nullptr);
    }
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = MessageWindowProc;
    wc.hInstance = module_;
    wc.lpszClassName = kMessageWindowClass;
    RegisterClassExW(&wc);
    messageWindow_ = CreateWindowExW(0, kMessageWindowClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, module_, nullptr);
    return messageWindow_;
}

// -- SessionHost ----------------------------------------------------------------------------

// Posted so the WebView2 event that produced it unwinds first; the state mirrors are already
// updated when the callback runs.
void Core::emitEvent(const std::string &type, const std::string &payload) {
    refreshStateMirrors();
    debugLog("event %s %.300s", type.c_str(), payload.c_str());
    std::string *pair = new std::string[2]{type, payload};
    if (!PostMessageW(messageWindow(), WMA_EVENT, 0, reinterpret_cast<LPARAM>(pair))) {
        delete[] pair;
    }
}

void Core::onPostedEvent(std::string *pair) {
    if (pair == nullptr) {
        return;
    }
    StashNativeDesktopEventCallback cb = callback_;
    if (cb != nullptr) {
        cb(pair[0].c_str(), pair[1].c_str(), callbackUserData_);
    }
    delete[] pair;
}

// Hides the surface now (isLive turns false, IsCurrentlyPresented follows the session) and
// destroys the controller and windows once the current WebView2 callback has unwound.
void Core::closeSurface() {
    webview::hideController();
    presenter_->hide();
    KillTimer(messageWindow(), TIMER_STALL);
    KillTimer(messageWindow(), TIMER_DEADLINE);
    if (!teardownPending_) {
        teardownPending_ = true;
        PostMessageW(messageWindow(), WMA_TEARDOWN, 0, 0);
    }
    refreshStateMirrors();
}

void Core::onPostedTeardown() {
    flushPendingTeardown();
}

void Core::flushPendingTeardown() {
    if (!teardownPending_) {
        return;
    }
    teardownPending_ = false;
    webview::closeSessionController();
    presenter_->teardown();
}

void Core::openSystemBrowser(const std::string &url) {
    ShellExecuteW(nullptr, L"open", widen(url).c_str(), nullptr, nullptr, SW_SHOWNORMAL);
}

void Core::openDeeplinkExternally(const std::string &url) {
    HINSTANCE result = ShellExecuteW(nullptr, L"open", widen(url).c_str(), nullptr, nullptr, SW_SHOWNORMAL);
    if (reinterpret_cast<INT_PTR>(result) <= 32) {
        debugLog("no handler for deeplink %s", url.c_str());
    }
}

void Core::log(const std::string &message) {
    debugLog("%s", message.c_str());
}

// -- ABI ------------------------------------------------------------------------------------

void Core::setEventCallback(StashNativeDesktopEventCallback callback, void *userData) {
    callback_ = callback;
    callbackUserData_ = userData;
}

void Core::setHostWindow(HWND hwnd) {
    explicitHost_ = hwnd;
}

Session *Core::sessionForId(unsigned long sessionId) {
    if (!session_ || sessionId != sessionId_) {
        return nullptr;
    }
    return session_.get();
}

void Core::refreshStateMirrors() {
    presentedMirror_ = session_ && session_->isPresented();
    processingMirror_ = session_ && session_->isPurchaseProcessing();
}

bool Core::systemPrefersDark() const {
    DWORD value = 1;
    DWORD size = sizeof(value);
    LSTATUS status = RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                                  L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &value, &size);
    return status == ERROR_SUCCESS && value == 0;
}

struct FindHostData {
    DWORD pid;
    HWND exclude;
    HWND best;
    long bestArea;
};

static BOOL CALLBACK FindHostEnumProc(HWND hwnd, LPARAM lParam) {
    FindHostData *data = reinterpret_cast<FindHostData *>(lParam);
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid != data->pid || !IsWindowVisible(hwnd) || hwnd == data->exclude) {
        return TRUE;
    }
    RECT rc;
    GetWindowRect(hwnd, &rc);
    long area = (rc.right - rc.left) * (rc.bottom - rc.top);
    if (area > data->bestArea) {
        data->bestArea = area;
        data->best = hwnd;
    }
    return TRUE;
}

HWND Core::findHostWindow() {
    if (explicitHost_ != nullptr && IsWindow(explicitHost_)) {
        return explicitHost_;
    }
    HWND active = GetActiveWindow();
    if (active != nullptr && IsWindowVisible(active)) {
        return active;
    }
    HWND foreground = GetForegroundWindow();
    DWORD pid = 0;
    if (foreground != nullptr) {
        GetWindowThreadProcessId(foreground, &pid);
        if (pid == GetCurrentProcessId() && IsWindowVisible(foreground)) {
            return foreground;
        }
    }
    FindHostData data = {GetCurrentProcessId(), presenter_->dialogOwner(), nullptr, 0};
    EnumWindows(FindHostEnumProc, reinterpret_cast<LPARAM>(&data));
    return data.best;
}

void Core::open(const std::string &url, const SurfaceConfig &config) {
    if (url.empty()) {
        debugLog("open ignored, empty URL");
        return;
    }
    flushPendingTeardown();
    if (session_ && session_->isPresented()) {
        // Block only when a presentation is live. A stale flag with nothing on screen is cleared
        // and the open proceeds, rather than returning silently.
        if (presenter_->isLive()) {
            debugLog("open ignored, checkout already presented");
            return;
        }
        debugLog("clearing stale presentation guard before opening");
        session_->reset();
        flushPendingTeardown();
    }

    bool systemDark = systemPrefersDark();
    sessionId_++;
    session_ = std::make_unique<Session>(*this, config, systemDark);
    uint32_t sheetArgb = theme::sheetBackgroundArgb(config.backgroundColor, systemDark);
    std::string themed = session_->themedUrl(url);
    bool dark = session_->themeIsDark();

    bool attached = false;
    if (config.presentation == Presentation::Attached) {
        HWND host = findHostWindow();
        if (host != nullptr) {
            attached = presenter_->presentAttached(host, config, sheetArgb);
        } else {
            debugLog("no host window, presenting in a standalone window");
        }
    }
    if (!attached) {
        presenter_->presentStandalone(config, sheetArgb);
    }
    refreshStateMirrors();

    unsigned long id = sessionId_;
    SurfaceConfig configCopy = config;
    webview::ensureEnvironment(
        [id, themed, configCopy, sheetArgb, dark]() {
            if (Core::instance().sessionForId(id) != nullptr) {
                webview::startSession(id, themed, configCopy, sheetArgb, dark);
            }
        },
        [id]() {
            Session *session = Core::instance().sessionForId(id);
            if (session != nullptr) {
                session->handleNetworkError();
                Core::instance().refreshStateMirrors();
            }
        });
}

void Core::openBrowser(const std::string &url) {
    if (url.empty()) {
        return;
    }
    openSystemBrowser(url::appendThemeQueryParameter(url, systemPrefersDark()));
}

void Core::dismiss() {
    if (session_) {
        session_->dismiss();
        refreshStateMirrors();
    }
}

void Core::resetPresentationState() {
    if (session_) {
        session_->reset();
    }
    closeSurface();
    flushPendingTeardown();
    refreshStateMirrors();
}

void Core::requestUserDismiss() {
    if (session_) {
        session_->requestUserDismiss();
        refreshStateMirrors();
    }
}

void Core::prewarm() {
    webview::ensureEnvironment([]() { webview::prewarm(); }, []() {});
}

void Core::shutdown() {
    if (session_) {
        session_->reset();
        session_.reset();
    }
    closeSurface();
    flushPendingTeardown();
    webview::releaseAll();
    callback_ = nullptr;
    callbackUserData_ = nullptr;
    refreshStateMirrors();
}

void Core::onTimer(UINT_PTR id) {
    webview::onTimer(id);
}

}  // namespace win
}  // namespace desktop
}  // namespace stash

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        stash::desktop::win::Core::instance().setModuleInstance(instance);
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}
