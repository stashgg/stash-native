// Internal declarations of the Windows host. One Core drives the shared Session; the Presenter
// owns the Win32 windows; the WebView2 layer owns the environment, controllers and load timers.
// Single-threaded: everything runs on the thread that owns the host window's message loop.
#ifndef STASH_NATIVE_CARD_PRIVATE_HPP
#define STASH_NATIVE_CARD_PRIVATE_HPP

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
// COM base types the MIDL-generated WebView2.h relies on; windows.h skips them with WIN32_LEAN_AND_MEAN.
#include <objbase.h>

#include <atomic>
#include <functional>
#include <memory>
#include <string>

#include "WebView2.h"

#include "StashDesktopConfig.h"
#include "StashDesktopSession.h"
#include "StashNativeDesktop.h"

namespace stash {
namespace desktop {
namespace win {

// -- Strings and logging --------------------------------------------------------------------

std::wstring widen(const std::string &utf8);
std::string narrow(const wchar_t *utf16);
void debugLog(const char *fmt, ...);

// -- COM callback helpers (no WRL, keeps the toolchain requirements minimal) -----------------

template <typename TIface, typename TA, typename TB>
class Callback2 final : public TIface {
public:
    using Fn = std::function<HRESULT(TA, TB)>;
    Callback2(REFIID iid, Fn fn) : iid_(iid), fn_(std::move(fn)), refs_(1) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (ppv == nullptr) {
            return E_POINTER;
        }
        if (IsEqualIID(riid, iid_) || IsEqualIID(riid, IID_IUnknown)) {
            *ppv = static_cast<TIface *>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return static_cast<ULONG>(InterlockedIncrement(&refs_)); }
    ULONG STDMETHODCALLTYPE Release() override {
        ULONG r = static_cast<ULONG>(InterlockedDecrement(&refs_));
        if (r == 0) {
            delete this;
        }
        return r;
    }
    HRESULT STDMETHODCALLTYPE Invoke(TA a, TB b) override { return fn_(a, b); }

private:
    ~Callback2() = default;
    IID iid_;
    Fn fn_;
    volatile LONG refs_;
};

// Created with one reference; the callee AddRefs, the caller releases after handing it over.
#define STASH_CALLBACK(TIface, TA, TB, lambda) (new stash::desktop::win::Callback2<TIface, TA, TB>(IID_##TIface, (lambda)))

template <typename T>
void safeRelease(T *&p) {
    if (p != nullptr) {
        p->Release();
        p = nullptr;
    }
}

// -- Presenter (Win32 surface) --------------------------------------------------------------

class Core;

class Presenter {
public:
    explicit Presenter(Core &core);
    ~Presenter();

    // Attached card / modal over the host window's client area. False when the host is invalid.
    bool presentAttached(HWND host, const SurfaceConfig &config, uint32_t sheetArgb);
    // Standalone top-level window (editor play mode / no host window).
    void presentStandalone(const SurfaceConfig &config, uint32_t sheetArgb);

    // Parent HWND and bounds for the WebView2 controller.
    HWND webViewParent() const;
    RECT webViewBounds() const;

    void updateTrustHeader(const std::string &url);
    void setLoading(bool loading);

    // Host-resize tracking; true when the card rect changed (controller bounds must follow).
    bool layout();

    // Hide immediately (isLive turns false), then destroy on the deferred teardown.
    void hide();
    void teardown();

    // Something of ours is on screen and its window still exists.
    bool isLive() const;
    HWND dialogOwner() const;
    // True while destroyWindows() runs, so the backdrop's WM_DESTROY can tell our own teardown
    // from the host window being destroyed underneath it.
    bool destroying() const { return destroying_; }

    // Window-procedure hooks.
    void paintCard(HWND hwnd);
    void paintSpinner(HWND hwnd);
    void drawCloseButton(const DRAWITEMSTRUCT *item);
    void onSpinnerTick(HWND hwnd);
    void onFadeTick(HWND hwnd);
    void onStandaloneResized();

private:
    struct Metrics {
        RECT client;
        RECT card;
        int headerHeight;
        double scale;
    };
    Metrics computeMetrics() const;
    void applyBackdropRegion(const Metrics &m);
    void registerClasses();
    void drawTrustHeader(HDC dc, int width, int headerHeight, double scale);
    void destroyWindows();

    Core &core_;
    HWND host_ = nullptr;
    bool hostStyleModified_ = false;
    bool destroying_ = false;
    HWND backdrop_ = nullptr;
    HWND card_ = nullptr;
    HWND closeButton_ = nullptr;
    HWND spinner_ = nullptr;
    HWND standalone_ = nullptr;
    bool live_ = false;
    bool hidden_ = false;
    SurfaceConfig config_;
    uint32_t sheetArgb_ = 0xFF1E1E1E;
    bool dark_ = true;
    std::string headerHost_;
    std::string headerScheme_;
    int backdropAlpha_ = 0;
    int spinnerAngle_ = 0;
    int lastClientWidth_ = -1;
    int lastClientHeight_ = -1;
    RECT lastCard_ = {};
    static bool classesRegistered_;
};

// -- Core -----------------------------------------------------------------------------------

class Core : public SessionHost {
public:
    static Core &instance();

    // SessionHost.
    void emitEvent(const std::string &type, const std::string &payload) override;
    void closeSurface() override;
    void openSystemBrowser(const std::string &url) override;
    void openDeeplinkExternally(const std::string &url) override;
    void log(const std::string &message) override;

    // ABI.
    void setEventCallback(StashNativeDesktopEventCallback callback, void *userData);
    void setHostWindow(HWND hwnd);
    void open(const std::string &url, const SurfaceConfig &config);
    void openBrowser(const std::string &url);
    void dismiss();
    void resetPresentationState();
    void prewarm();
    void shutdown();
    bool isCurrentlyPresented() const { return presentedMirror_.load(); }
    bool isPurchaseProcessing() const { return processingMirror_.load(); }
    void setInspectable(bool enabled) { inspectable_ = enabled; }
    bool inspectable() const { return inspectable_; }

    // Presenter -> core.
    void requestUserDismiss();
    // The attached host window is being destroyed: the presentation cannot outlive it, so the
    // session ends with dialogDismissed regardless of processing or modal rules.
    void hostWindowClosing();
    Presenter &presenter() { return *presenter_; }
    HINSTANCE moduleInstance() const { return module_; }
    void setModuleInstance(HINSTANCE instance) { module_ = instance; }
    HWND messageWindow();

    // WebView2 layer -> core.
    Session *sessionForId(unsigned long sessionId);
    unsigned long currentSessionId() const { return sessionId_; }
    void refreshStateMirrors();
    bool systemPrefersDark() const;

    // Posted work.
    void onPostedEvent(std::string *pair);
    void onPostedTeardown();
    void onTimer(UINT_PTR id);

private:
    Core();
    ~Core() override;
    HWND findHostWindow();
    void flushPendingTeardown();

    HINSTANCE module_ = nullptr;
    HWND messageWindow_ = nullptr;
    HWND explicitHost_ = nullptr;
    std::unique_ptr<Presenter> presenter_;
    std::unique_ptr<Session> session_;
    unsigned long sessionId_ = 0;
    bool teardownPending_ = false;
    bool inspectable_ = false;
    std::atomic<bool> presentedMirror_;
    std::atomic<bool> processingMirror_;
    StashNativeDesktopEventCallback callback_ = nullptr;
    void *callbackUserData_ = nullptr;
};

// -- WebView2 layer (StashNativeCardWebView.cpp) --------------------------------------------

namespace webview {

// Creates the environment when needed and runs the continuation once it exists; the
// continuation is dropped (with a networkError on the session) when creation fails.
void ensureEnvironment(std::function<void()> onReady, std::function<void()> onFailed);
bool hasEnvironment();

// Creates (or adopts the prewarmed) controller inside the presenter's parent window for the
// current session, wires events, injects the scripts and starts the load.
void startSession(unsigned long sessionId, const std::string &url, const SurfaceConfig &config, uint32_t sheetArgb, bool dark);
// Reparent / resize after a layout pass.
void applyBounds();
// Hides the session's controller now; closeSessionController destroys it later.
void hideController();
// Closes the session's controller; the prewarmed controller is untouched.
void closeSessionController();
void prewarm();
void releaseAll();
void onTimer(UINT_PTR id);

}  // namespace webview

// Message-window messages and timers.
const UINT WMA_EVENT = WM_APP + 41;
const UINT WMA_TEARDOWN = WM_APP + 42;
const UINT_PTR TIMER_STALL = 11;
const UINT_PTR TIMER_DEADLINE = 12;
const UINT_PTR TIMER_LAYOUT = 13;
const UINT_PTR TIMER_FADE = 14;
const UINT_PTR TIMER_SPIN = 15;

}  // namespace win
}  // namespace desktop
}  // namespace stash

#endif
