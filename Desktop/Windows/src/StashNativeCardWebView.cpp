// WebView2 layer: environment (one per process, per-game user data folder), the prewarmed
// controller, the session controller and its event wiring, script injection, and the load
// policy timers (stall reload after 1.25 s up to twice, 15 s deadline, one reload after a
// renderer death). Mirrors StashNativeCardWebViewDelegates on macOS.

#include "StashNativeCardPrivate.hpp"

#include <shlobj.h>

#include <vector>

#include "StashDesktopTheme.h"
#include "StashDesktopUrl.h"
#include "StashDesktopWebMessage.hpp"
#include "StashSdkScript.h"

namespace stash {
namespace desktop {
namespace win {
namespace webview {

namespace {

struct Waiter {
    std::function<void()> onReady;
    std::function<void()> onFailed;
};

struct State {
    bool comInitialized = false;
    // Retires an environment-creation completion that outlives releaseAll().
    unsigned long environmentGeneration = 0;
    ICoreWebView2Environment *environment = nullptr;
    bool environmentCreating = false;
    std::vector<Waiter> waiters;

    HWND prewarmHost = nullptr;
    ICoreWebView2Controller *prewarmController = nullptr;
    ICoreWebView2 *prewarmWebView = nullptr;

    ICoreWebView2Controller *controller = nullptr;
    ICoreWebView2 *webView = nullptr;
    // A session's own CreateCoreWebView2Controller is in flight: a prewarm completion landing
    // now must not be kept, or two controllers would share the document-script state.
    bool controllerCreating = false;
    unsigned long sessionId = 0;
    // Document scripts: the bridge script is requested (registered) and confirmed by WebView2
    // (ready); pendingScripts counts registrations (bridge and dark sheet) whose completion is
    // still outstanding, and a checkout waits for all of them before its first navigation. The
    // generation retires completions from a webview that has since been closed.
    bool sdkScriptRegistered = false;
    bool sdkScriptReady = false;
    int pendingScripts = 0;
    bool navigateWhenScriptReady = false;
    unsigned long scriptGeneration = 0;
    bool wired = false;
    std::wstring darkScriptId;

    std::wstring checkoutUrl;
    bool allowFileUrls = false;
    bool dark = false;
    uint32_t sheetArgb = 0xFF1E1E1E;
    bool initialLoadComplete = false;
    bool firstNavigationDone = false;
    // Navigate() for the checkout has been called: navigation events before that belong to the
    // prewarm placeholder, not to the session.
    bool checkoutNavigateCalled = false;
    int stallReloads = 0;
    bool processFailedRecoveryUsed = false;
    ULONGLONG pageLoadStart = 0;
    // The checkout's own navigation; completions of superseded loads (the prewarm placeholder) are ignored.
    UINT64 checkoutNavigationId = 0;
};

State g;

const wchar_t *kPrewarmClass = L"StashNativeDesktopPrewarm";
bool g_prewarmClassRegistered = false;

Session *currentSession() {
    return Core::instance().sessionForId(g.sessionId);
}

void emitError(const std::string &message) {
    Core::instance().emitEvent(STASH_NATIVE_DESKTOP_EVENT_ERROR, message);
}

void failSession() {
    Session *session = currentSession();
    if (session != nullptr) {
        session->handleNetworkError();
        Core::instance().refreshStateMirrors();
    }
}

void killLoadTimers() {
    HWND wnd = Core::instance().messageWindow();
    KillTimer(wnd, TIMER_STALL);
    KillTimer(wnd, TIMER_DEADLINE);
}

// Stall retries are for network stalls; a local file that has not committed yet is just slow.
void startLoadTimers() {
    HWND wnd = Core::instance().messageWindow();
    SetTimer(wnd, TIMER_DEADLINE, static_cast<UINT>(kNetworkDeadlineSeconds * 1000), nullptr);
    bool fileCheckout = url::scheme(narrow(g.checkoutUrl.c_str())) == "file";
    if (!fileCheckout && g.stallReloads < kMaxStallReloads) {
        SetTimer(wnd, TIMER_STALL, static_cast<UINT>(kStallRetrySeconds * 1000), nullptr);
    } else {
        KillTimer(wnd, TIMER_STALL);
    }
}

void markInitialLoadComplete() {
    if (g.initialLoadComplete) {
        return;
    }
    g.initialLoadComplete = true;
    killLoadTimers();
}

std::wstring userDataFolder() {
    // The full image path, however long: a truncated path would hash like another install's.
    std::vector<wchar_t> buffer(MAX_PATH);
    while (true) {
        DWORD length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
        if (length == 0) {
            buffer[0] = L'\0';
            break;
        }
        if (length < buffer.size() - 1 || buffer.size() >= 65536) {
            break;
        }
        buffer.resize(buffer.size() * 2);
    }
    std::wstring exePath(buffer.data());
    wchar_t *localAppData = nullptr;
    size_t len = 0;
    std::wstring base;
    if (_wdupenv_s(&localAppData, &len, L"LOCALAPPDATA") == 0 && localAppData != nullptr) {
        base = localAppData;
        free(localAppData);
    }
    std::wstring folder = userDataFolderFor(base, exePath);
    SHCreateDirectoryExW(nullptr, folder.c_str(), nullptr);
    return folder;
}

void runWaiters(bool ready) {
    std::vector<Waiter> waiters;
    waiters.swap(g.waiters);
    for (Waiter &w : waiters) {
        if (ready) {
            if (w.onReady) {
                w.onReady();
            }
        } else if (w.onFailed) {
            w.onFailed();
        }
    }
}

void navigateToCheckout() {
    if (g.webView == nullptr) {
        return;
    }
    Core::instance().presenter().setLoading(true);
    std::string origin = narrow(g.checkoutUrl.c_str());
    debugLog("navigate %s://%s", stash::desktop::url::scheme(origin).c_str(), stash::desktop::url::host(origin).c_str());
    g.checkoutNavigateCalled = true;
    HRESULT hr = g.webView->Navigate(g.checkoutUrl.c_str());
    if (FAILED(hr)) {
        // The error payload is wrapper-logged: a code, never the (signed) URL.
        char code[48];
        _snprintf_s(code, _TRUNCATE, "navigate failed hr=0x%08X", static_cast<unsigned>(hr));
        debugLog("%s", code);
        emitError(code);
        failSession();
    }
}

void startCheckoutNavigation();

// AddScriptToExecuteOnDocumentCreated completes asynchronously and a script is only guaranteed
// on navigations started after its completion. A checkout must not navigate before every
// registered script (the bridge, the dark sheet) is confirmed, or its first document would
// load without window.stash_sdk or without the theme.
void scriptRegistrationSettled() {
    if (g.pendingScripts > 0 || !g.navigateWhenScriptReady) {
        return;
    }
    g.navigateWhenScriptReady = false;
    if (g.sdkScriptReady) {
        startCheckoutNavigation();
    } else {
        emitError("bridge script registration failed");
        failSession();
    }
}

void registerScript(ICoreWebView2 *webView, const std::string &script, bool isSdk) {
    if (isSdk) {
        g.sdkScriptRegistered = true;
        g.sdkScriptReady = false;
    }
    g.pendingScripts++;
    unsigned long generation = g.scriptGeneration;
    auto *handler = STASH_CALLBACK(ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler, HRESULT, LPCWSTR,
                                   ([generation, isSdk](HRESULT result, LPCWSTR id) -> HRESULT {
                                       if (generation != g.scriptGeneration) {
                                           return S_OK;
                                       }
                                       g.pendingScripts--;
                                       if (FAILED(result)) {
                                           debugLog("%s script registration failed hr=0x%08X", isSdk ? "bridge" : "dark sheet",
                                                    static_cast<unsigned>(result));
                                           if (isSdk) {
                                               g.sdkScriptRegistered = false;
                                           }
                                       } else if (isSdk) {
                                           g.sdkScriptReady = true;
                                       } else if (id != nullptr) {
                                           g.darkScriptId = id;
                                       }
                                       scriptRegistrationSettled();
                                       return S_OK;
                                   }));
    HRESULT hr = webView->AddScriptToExecuteOnDocumentCreated(widen(script).c_str(), handler);
    handler->Release();
    if (FAILED(hr)) {
        // Failed synchronously: the completion never runs, so settle the registration here.
        debugLog("%s script registration refused hr=0x%08X", isSdk ? "bridge" : "dark sheet", static_cast<unsigned>(hr));
        g.pendingScripts--;
        if (isSdk) {
            g.sdkScriptRegistered = false;
        }
        scriptRegistrationSettled();
    }
}

void wireWebView(ICoreWebView2 *webView) {
    EventRegistrationToken token;
    unsigned long id = g.sessionId;

    addHandler(&ICoreWebView2::add_WebMessageReceived, webView,
        STASH_CALLBACK(ICoreWebView2WebMessageReceivedEventHandler, ICoreWebView2 *, ICoreWebView2WebMessageReceivedEventArgs *,
                       ([id](ICoreWebView2 *sender, ICoreWebView2WebMessageReceivedEventArgs *args) -> HRESULT {
                           Session *session = Core::instance().sessionForId(id);
                           if (session == nullptr) {
                               return S_OK;
                           }
                           // Only the top document may speak to the host.
                           LPWSTR source = nullptr;
                           LPWSTR top = nullptr;
                           bool fromTop = SUCCEEDED(args->get_Source(&source)) && source != nullptr &&
                                          SUCCEEDED(sender->get_Source(&top)) && top != nullptr && wcscmp(source, top) == 0;
                           if (source != nullptr) {
                               CoTaskMemFree(source);
                           }
                           if (top != nullptr) {
                               CoTaskMemFree(top);
                           }
                           if (!fromTop) {
                               debugLog("web message from a sub-frame ignored");
                               return S_OK;
                           }
                           LPWSTR json = nullptr;
                           if (SUCCEEDED(args->get_WebMessageAsJson(&json)) && json != nullptr) {
                               std::string type;
                               std::string payload;
                               if (parseWebMessage(narrow(json), type, payload)) {
                                   session->handleMessage(type, payload);
                                   Core::instance().refreshStateMirrors();
                               }
                               CoTaskMemFree(json);
                           }
                           return S_OK;
                       })),
        &token);

    addHandler(&ICoreWebView2::add_NavigationStarting, webView,
        STASH_CALLBACK(ICoreWebView2NavigationStartingEventHandler, ICoreWebView2 *, ICoreWebView2NavigationStartingEventArgs *,
                       ([id](ICoreWebView2 *, ICoreWebView2NavigationStartingEventArgs *args) -> HRESULT {
                           Session *session = Core::instance().sessionForId(id);
                           LPWSTR uri = nullptr;
                           if (FAILED(args->get_Uri(&uri)) || uri == nullptr) {
                               return S_OK;
                           }
                           std::string url = narrow(uri);
                           CoTaskMemFree(uri);
                           // The prewarm placeholder is identified by state, not by its URL: anything
                           // starting before the checkout's Navigate() call, or an about:blank
                           // arriving before the checkout's own start was recorded when the checkout
                           // is not about:blank itself. A caller opening about:blank is a checkout.
                           bool placeholder = !g.checkoutNavigateCalled ||
                                              (url == "about:blank" && g.checkoutNavigationId == 0 &&
                                               narrow(g.checkoutUrl.c_str()).compare(0, 11, "about:blank") != 0);
                           if (placeholder) {
                               return S_OK;
                           }
                           if (session == nullptr || session->decideMainFrameNavigation(url) == NavigationDecision::Cancel) {
                               args->put_Cancel(TRUE);
                           } else {
                               args->get_NavigationId(&g.checkoutNavigationId);
                           }
                           Core::instance().refreshStateMirrors();
                           return S_OK;
                       })),
        &token);

    addHandler(&ICoreWebView2::add_FrameNavigationStarting, webView,
        STASH_CALLBACK(ICoreWebView2NavigationStartingEventHandler, ICoreWebView2 *, ICoreWebView2NavigationStartingEventArgs *,
                       ([id](ICoreWebView2 *, ICoreWebView2NavigationStartingEventArgs *args) -> HRESULT {
                           Session *session = Core::instance().sessionForId(id);
                           LPWSTR uri = nullptr;
                           if (FAILED(args->get_Uri(&uri)) || uri == nullptr) {
                               return S_OK;
                           }
                           std::string url = narrow(uri);
                           CoTaskMemFree(uri);
                           if (session == nullptr || session->decideSubFrameNavigation(url) == NavigationDecision::Cancel) {
                               args->put_Cancel(TRUE);
                           }
                           Core::instance().refreshStateMirrors();
                           return S_OK;
                       })),
        &token);

    // Document bytes arrived for the main frame: the stall / deadline timers are done.
    addHandler(&ICoreWebView2::add_ContentLoading, webView,
        STASH_CALLBACK(ICoreWebView2ContentLoadingEventHandler, ICoreWebView2 *, ICoreWebView2ContentLoadingEventArgs *,
                       ([id](ICoreWebView2 *, ICoreWebView2ContentLoadingEventArgs *args) -> HRESULT {
                           UINT64 navigationId = 0;
                           args->get_NavigationId(&navigationId);
                           // Navigations overlap: only the checkout's own document counts.
                           if (Core::instance().sessionForId(id) != nullptr && navigationId == g.checkoutNavigationId) {
                               debugLog("content loading");
                               markInitialLoadComplete();
                           }
                           return S_OK;
                       })),
        &token);

    addHandler(&ICoreWebView2::add_NavigationCompleted, webView,
        STASH_CALLBACK(ICoreWebView2NavigationCompletedEventHandler, ICoreWebView2 *, ICoreWebView2NavigationCompletedEventArgs *,
                       ([id](ICoreWebView2 *sender, ICoreWebView2NavigationCompletedEventArgs *args) -> HRESULT {
                           Session *session = Core::instance().sessionForId(id);
                           if (session == nullptr) {
                               return S_OK;
                           }
                           UINT64 navigationId = 0;
                           args->get_NavigationId(&navigationId);
                           if (navigationId != g.checkoutNavigationId) {
                               // A superseded load (the prewarm placeholder, a cancelled first attempt).
                               return S_OK;
                           }
                           BOOL success = FALSE;
                           args->get_IsSuccess(&success);
                           COREWEBVIEW2_WEB_ERROR_STATUS status = COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN;
                           args->get_WebErrorStatus(&status);
                           if (!success && status == COREWEBVIEW2_WEB_ERROR_STATUS_OPERATION_CANCELED) {
                               // Our own policy cancels and superseded loads are not failures.
                               return S_OK;
                           }
                           bool first = !g.firstNavigationDone;
                           g.firstNavigationDone = true;
                           debugLog("navigation completed success=%d status=%d first=%d", success ? 1 : 0, static_cast<int>(status), first ? 1 : 0);
                           int httpStatus = 0;
                           ICoreWebView2NavigationCompletedEventArgs2 *args2 = nullptr;
                           if (SUCCEEDED(args->QueryInterface(IID_ICoreWebView2NavigationCompletedEventArgs2,
                                                              reinterpret_cast<void **>(&args2))) && args2 != nullptr) {
                               args2->get_HttpStatusCode(&httpStatus);
                               args2->Release();
                           }
                           if (!success || (first && httpStatus >= 400)) {
                               debugLog("navigation failed status=%d http=%d first=%d", static_cast<int>(status), httpStatus, first ? 1 : 0);
                               if (first) {
                                   session->handleNetworkError();
                               } else {
                                   session->dismiss();
                               }
                               Core::instance().refreshStateMirrors();
                               return S_OK;
                           }
                           LPWSTR source = nullptr;
                           if (SUCCEEDED(sender->get_Source(&source)) && source != nullptr) {
                               Core::instance().presenter().updateTrustHeader(narrow(source));
                               CoTaskMemFree(source);
                           }
                           Core::instance().presenter().setLoading(false);
                           double loadTimeMs = static_cast<double>(GetTickCount64() - g.pageLoadStart);
                           session->handlePageFinished(loadTimeMs);
                           Core::instance().refreshStateMirrors();
                           return S_OK;
                       })),
        &token);

    addHandler(&ICoreWebView2::add_SourceChanged, webView,
        STASH_CALLBACK(ICoreWebView2SourceChangedEventHandler, ICoreWebView2 *, ICoreWebView2SourceChangedEventArgs *,
                       ([id](ICoreWebView2 *sender, ICoreWebView2SourceChangedEventArgs *) -> HRESULT {
                           if (Core::instance().sessionForId(id) == nullptr) {
                               return S_OK;
                           }
                           LPWSTR source = nullptr;
                           if (SUCCEEDED(sender->get_Source(&source)) && source != nullptr) {
                               Core::instance().presenter().updateTrustHeader(narrow(source));
                               CoTaskMemFree(source);
                           }
                           return S_OK;
                       })),
        &token);

    // target=_blank / window.open: external browser, the checkout stays presented.
    addHandler(&ICoreWebView2::add_NewWindowRequested, webView,
        STASH_CALLBACK(ICoreWebView2NewWindowRequestedEventHandler, ICoreWebView2 *, ICoreWebView2NewWindowRequestedEventArgs *,
                       ([id](ICoreWebView2 *, ICoreWebView2NewWindowRequestedEventArgs *args) -> HRESULT {
                           args->put_Handled(TRUE);
                           Session *session = Core::instance().sessionForId(id);
                           LPWSTR uri = nullptr;
                           if (session != nullptr && SUCCEEDED(args->get_Uri(&uri)) && uri != nullptr) {
                               session->handleNewWindow(narrow(uri));
                               CoTaskMemFree(uri);
                           }
                           return S_OK;
                       })),
        &token);

    addHandler(&ICoreWebView2::add_WindowCloseRequested, webView,
        STASH_CALLBACK(ICoreWebView2WindowCloseRequestedEventHandler, ICoreWebView2 *, IUnknown *,
                       ([id](ICoreWebView2 *, IUnknown *) -> HRESULT {
                           Session *session = Core::instance().sessionForId(id);
                           if (session != nullptr) {
                               session->handleWindowClose();
                               Core::instance().refreshStateMirrors();
                           }
                           return S_OK;
                       })),
        &token);

    // Renderer crashes are isolated from the game: one reload, then a network error.
    // A download never belongs in a checkout: cancelled and its UI hidden. Before the first
    // finished page nothing is on screen, so it is a network error (as the macOS host reports
    // a response WebKit would download); afterwards the shown page stays.
    ICoreWebView2_4 *webView4 = nullptr;
    if (SUCCEEDED(webView->QueryInterface(IID_ICoreWebView2_4, reinterpret_cast<void **>(&webView4))) && webView4 != nullptr) {
        addHandler(&ICoreWebView2_4::add_DownloadStarting, webView4,
            STASH_CALLBACK(ICoreWebView2DownloadStartingEventHandler, ICoreWebView2 *, ICoreWebView2DownloadStartingEventArgs *,
                           ([id](ICoreWebView2 *, ICoreWebView2DownloadStartingEventArgs *args) -> HRESULT {
                               args->put_Cancel(TRUE);
                               args->put_Handled(TRUE);
                               Session *session = Core::instance().sessionForId(id);
                               if (session != nullptr && !g.firstNavigationDone) {
                                   debugLog("download refused before the first page");
                                   session->handleNetworkError();
                                   Core::instance().refreshStateMirrors();
                               } else {
                                   debugLog("download refused");
                               }
                               return S_OK;
                           })),
            &token);
        webView4->Release();
    }

    addHandler(&ICoreWebView2::add_ProcessFailed, webView,
        STASH_CALLBACK(ICoreWebView2ProcessFailedEventHandler, ICoreWebView2 *, ICoreWebView2ProcessFailedEventArgs *,
                       ([id](ICoreWebView2 *sender, ICoreWebView2ProcessFailedEventArgs *args) -> HRESULT {
                           Session *session = Core::instance().sessionForId(id);
                           COREWEBVIEW2_PROCESS_FAILED_KIND kind;
                           if (session == nullptr || FAILED(args->get_ProcessFailedKind(&kind))) {
                               return S_OK;
                           }
                           debugLog("process failed kind=%d", static_cast<int>(kind));
                           bool renderer = kind == COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_EXITED ||
                                           kind == COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_UNRESPONSIVE;
                           if (renderer && !g.processFailedRecoveryUsed) {
                               g.processFailedRecoveryUsed = true;
                               Core::instance().emitEvent(STASH_NATIVE_DESKTOP_EVENT_WEB_PROCESS_CRASHED, "reloading");
                               g.initialLoadComplete = false;
                               g.firstNavigationDone = false;
                               Core::instance().presenter().setLoading(true);
                               sender->Reload();
                               startLoadTimers();
                           } else if (renderer) {
                               Core::instance().emitEvent(STASH_NATIVE_DESKTOP_EVENT_WEB_PROCESS_CRASHED, "terminal");
                               session->handleNetworkError();
                           } else if (kind == COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED) {
                               Core::instance().emitEvent(STASH_NATIVE_DESKTOP_EVENT_WEB_PROCESS_CRASHED, "terminal");
                               session->handleNetworkError();
                               // The environment died with the browser process; the next open recreates it.
                               releaseAll();
                           }
                           Core::instance().refreshStateMirrors();
                           return S_OK;
                       })),
        &token);
}

void finishControllerSetup() {
    if (g.controller == nullptr || g.webView == nullptr) {
        emitError("webview creation failed");
        failSession();
        return;
    }
    ICoreWebView2Settings *settings = nullptr;
    if (SUCCEEDED(g.webView->get_Settings(&settings)) && settings != nullptr) {
        settings->put_AreDevToolsEnabled(Core::instance().inspectable() ? TRUE : FALSE);
        settings->put_AreDefaultContextMenusEnabled(FALSE);
        settings->put_IsStatusBarEnabled(FALSE);
        settings->put_IsZoomControlEnabled(FALSE);
        settings->put_AreDefaultScriptDialogsEnabled(TRUE);
        settings->Release();
    }
    ICoreWebView2Controller2 *controller2 = nullptr;
    if (SUCCEEDED(g.controller->QueryInterface(IID_ICoreWebView2Controller2, reinterpret_cast<void **>(&controller2))) &&
        controller2 != nullptr) {
        COREWEBVIEW2_COLOR color = {255, static_cast<BYTE>((g.sheetArgb >> 16) & 0xFF), static_cast<BYTE>((g.sheetArgb >> 8) & 0xFF),
                                    static_cast<BYTE>(g.sheetArgb & 0xFF)};
        controller2->put_DefaultBackgroundColor(color);
        controller2->Release();
    }
    if (!g.sdkScriptRegistered) {
        registerScript(g.webView, STASH_SDK_SCRIPT_WEBVIEW2, true);
    }
    if (g.dark) {
        registerScript(g.webView, theme::darkSheetScript(g.sheetArgb), false);
    }
    if (!g.wired) {
        wireWebView(g.webView);
        g.wired = true;
    }

    EventRegistrationToken token;
    unsigned long id = g.sessionId;
    addHandler(&ICoreWebView2Controller::add_AcceleratorKeyPressed, g.controller,
        STASH_CALLBACK(ICoreWebView2AcceleratorKeyPressedEventHandler, ICoreWebView2Controller *, ICoreWebView2AcceleratorKeyPressedEventArgs *,
                       ([id](ICoreWebView2Controller *, ICoreWebView2AcceleratorKeyPressedEventArgs *args) -> HRESULT {
                           COREWEBVIEW2_KEY_EVENT_KIND kind;
                           UINT key = 0;
                           args->get_KeyEventKind(&kind);
                           args->get_VirtualKey(&key);
                           if (kind == COREWEBVIEW2_KEY_EVENT_KIND_KEY_DOWN && key == VK_ESCAPE &&
                               Core::instance().sessionForId(id) != nullptr) {
                               args->put_Handled(TRUE);
                               Core::instance().requestUserDismiss();
                           }
                           return S_OK;
                       })),
        &token);

    applyBounds();
    g.controller->put_IsVisible(TRUE);
    g.controller->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);

    g.navigateWhenScriptReady = true;
    if (g.pendingScripts > 0) {
        debugLog("waiting for %d document script registration(s) before navigating", g.pendingScripts);
    }
    scriptRegistrationSettled();
}

// First navigation of the session, once the bridge script is confirmed registered.
void startCheckoutNavigation() {
    Session *session = currentSession();
    if (session == nullptr || g.webView == nullptr) {
        return;
    }
    std::string url = narrow(g.checkoutUrl.c_str());
    if (url::scheme(url) == "file" && !g.allowFileUrls) {
        // WebView2 would refuse the file itself; run the policy so the refusal is reported the
        // same way (navigationBlocked, then networkError).
        session->decideMainFrameNavigation(url);
        Core::instance().refreshStateMirrors();
        return;
    }
    g.pageLoadStart = GetTickCount64();
    navigateToCheckout();
    startLoadTimers();
}

void registerPrewarmClass() {
    if (g_prewarmClassRegistered) {
        return;
    }
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = DefWindowProcW;
    wc.hInstance = Core::instance().moduleInstance();
    wc.lpszClassName = kPrewarmClass;
    RegisterClassExW(&wc);
    g_prewarmClassRegistered = true;
}

}  // namespace

bool hasEnvironment() {
    return g.environment != nullptr;
}

void ensureEnvironment(std::function<void()> onReady, std::function<void()> onFailed) {
    if (g.environment != nullptr) {
        onReady();
        return;
    }
    g.waiters.push_back({std::move(onReady), std::move(onFailed)});
    if (g.environmentCreating) {
        return;
    }
    if (!g.comInitialized) {
        HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        if (hr == RPC_E_CHANGED_MODE) {
            // The thread already runs a COM apartment. WebView2 needs an STA: an MTA thread
            // would show a surface and then fail to create the environment.
            APTTYPE type = APTTYPE_CURRENT;
            APTTYPEQUALIFIER qualifier = APTTYPEQUALIFIER_NONE;
            bool sta = SUCCEEDED(CoGetApartmentType(&type, &qualifier)) && (type == APTTYPE_STA || type == APTTYPE_MAINSTA);
            if (!sta) {
                emitError("WebView2 needs a single-threaded apartment: call the SDK from the thread that runs the "
                          "host window's message loop, not from an MTA thread");
                runWaiters(false);
                return;
            }
        }
        if (SUCCEEDED(hr) || hr == RPC_E_CHANGED_MODE) {
            g.comInitialized = true;
        }
    }
    LPWSTR version = nullptr;
    HRESULT versionResult = GetAvailableCoreWebView2BrowserVersionString(nullptr, &version);
    if (FAILED(versionResult) || version == nullptr) {
        emitError("WebView2 Runtime is not installed (preinstalled on Windows 11 and updated Windows 10; "
                  "otherwise install the Evergreen runtime)");
        runWaiters(false);
        return;
    }
    debugLog("WebView2 Runtime %S", version);
    CoTaskMemFree(version);

    g.environmentCreating = true;
    std::wstring folder = userDataFolder();
    unsigned long generation = g.environmentGeneration;
    auto *handler = STASH_CALLBACK(ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler, HRESULT, ICoreWebView2Environment *,
                                   ([generation](HRESULT result, ICoreWebView2Environment *environment) -> HRESULT {
                                       if (generation != g.environmentGeneration) {
                                           // releaseAll() ran meanwhile; a later open owns the waiters now.
                                           debugLog("stale environment completion ignored");
                                           return S_OK;
                                       }
                                       g.environmentCreating = false;
                                       if (FAILED(result) || environment == nullptr) {
                                           debugLog("environment creation failed hr=0x%08X", static_cast<unsigned>(result));
                                           emitError("WebView2 environment creation failed");
                                           runWaiters(false);
                                           return S_OK;
                                       }
                                       environment->AddRef();
                                       g.environment = environment;
                                       runWaiters(true);
                                       return S_OK;
                                   }));
    HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(nullptr, folder.c_str(), nullptr, handler);
    handler->Release();
    if (FAILED(hr)) {
        g.environmentCreating = false;
        debugLog("CreateCoreWebView2EnvironmentWithOptions failed hr=0x%08X", static_cast<unsigned>(hr));
        emitError("WebView2 environment creation failed to start");
        runWaiters(false);
    }
}

void startSession(unsigned long sessionId, const std::string &url, const SurfaceConfig &config, uint32_t sheetArgb, bool dark) {
    closeSessionController();
    g.sessionId = sessionId;
    g.checkoutUrl = widen(url);
    g.allowFileUrls = config.allowFileUrls;
    g.dark = dark;
    g.sheetArgb = sheetArgb;
    g.initialLoadComplete = false;
    g.firstNavigationDone = false;
    g.checkoutNavigateCalled = false;
    g.stallReloads = 0;
    g.processFailedRecoveryUsed = false;
    g.pageLoadStart = GetTickCount64();
    g.checkoutNavigationId = 0;

    HWND parent = Core::instance().presenter().webViewParent();
    if (parent == nullptr || g.environment == nullptr) {
        failSession();
        return;
    }

    if (g.prewarmController != nullptr) {
        debugLog("using prewarmed webview");
        g.controller = g.prewarmController;
        g.webView = g.prewarmWebView;
        g.prewarmController = nullptr;
        g.prewarmWebView = nullptr;
        // sdkScriptRegistered / sdkScriptReady carry over from the prewarm registration.
        g.wired = false;
        // The placeholder load may still be in flight; it must not reach the session.
        g.webView->Stop();
        g.controller->put_ParentWindow(parent);
        g.controller->NotifyParentWindowPositionChanged();
        finishControllerSetup();
        return;
    }

    auto *handler = STASH_CALLBACK(ICoreWebView2CreateCoreWebView2ControllerCompletedHandler, HRESULT, ICoreWebView2Controller *,
                                   ([sessionId](HRESULT result, ICoreWebView2Controller *controller) -> HRESULT {
                                       // Only the creation this completion belongs to is over: a late completion of
                                       // a dismissed session must not unblock a prewarm while the current session's
                                       // own creation is still in flight.
                                       if (g.sessionId == sessionId) {
                                           g.controllerCreating = false;
                                       }
                                       if (Core::instance().sessionForId(sessionId) == nullptr || g.sessionId != sessionId ||
                                           g.controller != nullptr) {
                                           if (controller != nullptr) {
                                               controller->Close();
                                           }
                                           return S_OK;
                                       }
                                       if (FAILED(result) || controller == nullptr) {
                                           debugLog("controller creation failed hr=0x%08X", static_cast<unsigned>(result));
                                           emitError("webview controller creation failed");
                                           failSession();
                                           return S_OK;
                                       }
                                       controller->AddRef();
                                       g.controller = controller;
                                       controller->get_CoreWebView2(&g.webView);
                                       g.sdkScriptRegistered = false;
                                       g.sdkScriptReady = false;
                                       g.wired = false;
                                       finishControllerSetup();
                                       return S_OK;
                                   }));
    g.controllerCreating = true;
    HRESULT hr = g.environment->CreateCoreWebView2Controller(parent, handler);
    handler->Release();
    if (FAILED(hr)) {
        g.controllerCreating = false;
        emitError("webview controller creation failed to start");
        failSession();
    }
}

void applyBounds() {
    if (g.controller == nullptr) {
        return;
    }
    RECT bounds = Core::instance().presenter().webViewBounds();
    g.controller->put_Bounds(bounds);
    g.controller->NotifyParentWindowPositionChanged();
}

void hideController() {
    if (g.controller != nullptr) {
        g.controller->put_IsVisible(FALSE);
    }
}

void closeSessionController() {
    killLoadTimers();
    if (g.controller != nullptr) {
        g.controller->Close();
    }
    safeRelease(g.webView);
    safeRelease(g.controller);
    g.controllerCreating = false;
    g.sdkScriptRegistered = false;
    g.sdkScriptReady = false;
    g.pendingScripts = 0;
    g.navigateWhenScriptReady = false;
    g.scriptGeneration++;
    g.wired = false;
    g.darkScriptId.clear();
}

void prewarm() {
    if (g.environment == nullptr || g.prewarmController != nullptr || g.controller != nullptr) {
        return;
    }
    registerPrewarmClass();
    if (g.prewarmHost == nullptr) {
        g.prewarmHost = CreateWindowExW(WS_EX_TOOLWINDOW, kPrewarmClass, L"", WS_POPUP, 0, 0, 1, 1, nullptr, nullptr,
                                        Core::instance().moduleInstance(), nullptr);
    }
    unsigned long generation = g.environmentGeneration;
    auto *handler = STASH_CALLBACK(ICoreWebView2CreateCoreWebView2ControllerCompletedHandler, HRESULT, ICoreWebView2Controller *,
                                   ([generation](HRESULT result, ICoreWebView2Controller *controller) -> HRESULT {
                                       if (FAILED(result) || controller == nullptr) {
                                           debugLog("prewarm controller creation failed hr=0x%08X", static_cast<unsigned>(result));
                                           return S_OK;
                                       }
                                       if (generation != g.environmentGeneration) {
                                           // Shutdown ran meanwhile: a controller of a retired environment must not be kept.
                                           controller->Close();
                                           return S_OK;
                                       }
                                       if (g.controller != nullptr || g.controllerCreating || g.prewarmController != nullptr) {
                                           // An open beat us to it (or is creating its own controller right now).
                                           controller->Close();
                                           return S_OK;
                                       }
                                       controller->AddRef();
                                       g.prewarmController = controller;
                                       controller->get_CoreWebView2(&g.prewarmWebView);
                                       controller->put_IsVisible(FALSE);
                                       if (g.prewarmWebView != nullptr) {
                                           registerScript(g.prewarmWebView, STASH_SDK_SCRIPT_WEBVIEW2, true);
                                           g.prewarmWebView->Navigate(L"about:blank");
                                       }
                                       debugLog("prewarmed webview ready");
                                       return S_OK;
                                   }));
    g.environment->CreateCoreWebView2Controller(g.prewarmHost, handler);
    handler->Release();
}

void releaseAll() {
    closeSessionController();
    if (g.prewarmController != nullptr) {
        g.prewarmController->Close();
    }
    safeRelease(g.prewarmWebView);
    safeRelease(g.prewarmController);
    if (g.prewarmHost != nullptr) {
        DestroyWindow(g.prewarmHost);
        g.prewarmHost = nullptr;
    }
    safeRelease(g.environment);
    g.environmentCreating = false;
    g.environmentGeneration++;
    g.waiters.clear();
}

void onTimer(UINT_PTR id) {
    Session *session = currentSession();
    if (session == nullptr || g.initialLoadComplete) {
        killLoadTimers();
        return;
    }
    if (id == TIMER_STALL) {
        KillTimer(Core::instance().messageWindow(), TIMER_STALL);
        if (g.stallReloads >= kMaxStallReloads) {
            return;
        }
        g.stallReloads += 1;
        debugLog("stall retry %d/%d", g.stallReloads, kMaxStallReloads);
        navigateToCheckout();
        startLoadTimers();
    } else if (id == TIMER_DEADLINE) {
        debugLog("load deadline reached after %d stall reload(s)", g.stallReloads);
        killLoadTimers();
        session->handleNetworkError();
        Core::instance().refreshStateMirrors();
    }
}

}  // namespace webview
}  // namespace win
}  // namespace desktop
}  // namespace stash
