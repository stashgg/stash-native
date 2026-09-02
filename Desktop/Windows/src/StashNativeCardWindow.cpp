// Win32 surface: dimmed layered backdrop over the host client area, rounded card with a native
// trust header (lock, host, close button) painted by the game process so the page cannot forge
// it, a spinner until the page loads, click-outside / Esc / close to dismiss, host-resize
// tracking. Or a standalone top-level window for editor play mode.

#include "StashNativeCardPrivate.hpp"

#include <windowsx.h>

#include <cmath>

#include "StashDesktopTheme.h"
#include "StashDesktopUrl.h"

namespace stash {
namespace desktop {
namespace win {

static const wchar_t *kClassBackdrop = L"StashNativeDesktopBackdrop";
static const wchar_t *kClassCard = L"StashNativeDesktopCard";
static const wchar_t *kClassSpinner = L"StashNativeDesktopSpinner";
static const wchar_t *kClassStandalone = L"StashNativeDesktopStandalone";

static const int kHeaderHeightPt = 36;
static const int kCornerRadiusPt = 14;
static const int kSpinnerSizePt = 44;
static const int kCloseButtonPt = 26;
static const int kBackdropTargetAlpha = 102;  // 40% black, same dim as mobile
static const int kIdCloseButton = 100;

bool Presenter::classesRegistered_ = false;

static double dpiScale(HWND hwnd) {
    UINT dpi = hwnd != nullptr ? GetDpiForWindow(hwnd) : 0;
    if (dpi == 0) {
        dpi = GetDpiForSystem();
    }
    return dpi > 0 ? dpi / 96.0 : 1.0;
}

static COLORREF colorFromArgb(uint32_t argb) {
    return RGB((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
}

static COLORREF blend(COLORREF base, COLORREF over, double amount) {
    auto mix = [amount](int a, int b) { return static_cast<int>(a + (b - a) * amount); };
    return RGB(mix(GetRValue(base), GetRValue(over)), mix(GetGValue(base), GetGValue(over)), mix(GetBValue(base), GetBValue(over)));
}

// -- Window procedures ----------------------------------------------------------------------

static LRESULT CALLBACK BackdropProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    Presenter &presenter = Core::instance().presenter();
    switch (msg) {
        case WM_LBUTTONDOWN:
            Core::instance().requestUserDismiss();
            return 0;
        case WM_PAINT: {
            PAINTSTRUCT ps;
            HDC dc = BeginPaint(hwnd, &ps);
            HBRUSH brush = CreateSolidBrush(RGB(0, 0, 0));
            FillRect(dc, &ps.rcPaint, brush);
            DeleteObject(brush);
            EndPaint(hwnd, &ps);
            return 0;
        }
        case WM_TIMER:
            if (wParam == TIMER_LAYOUT) {
                if (presenter.layout()) {
                    webview::applyBounds();
                }
                return 0;
            }
            if (wParam == TIMER_FADE) {
                presenter.onFadeTick(hwnd);
                return 0;
            }
            break;
        case WM_ERASEBKGND:
            return 1;
        case WM_DESTROY:
            // A child dies with its parent: unless this is our own teardown, the host window is
            // going away and the session must not stay "presented" over nothing.
            if (!presenter.destroying()) {
                Core::instance().hostWindowClosing();
            }
            break;
        default:
            break;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

static LRESULT CALLBACK CardProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    Presenter &presenter = Core::instance().presenter();
    switch (msg) {
        case WM_PAINT:
            presenter.paintCard(hwnd);
            return 0;
        case WM_DRAWITEM: {
            const DRAWITEMSTRUCT *item = reinterpret_cast<const DRAWITEMSTRUCT *>(lParam);
            if (item->CtlID == kIdCloseButton) {
                presenter.drawCloseButton(item);
                return TRUE;
            }
            break;
        }
        case WM_COMMAND:
            if (LOWORD(wParam) == kIdCloseButton) {
                Core::instance().requestUserDismiss();
                return 0;
            }
            break;
        case WM_KEYDOWN:
            if (wParam == VK_ESCAPE) {
                Core::instance().requestUserDismiss();
                return 0;
            }
            break;
        case WM_ERASEBKGND:
            return 1;
        default:
            break;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

static LRESULT CALLBACK SpinnerProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    Presenter &presenter = Core::instance().presenter();
    switch (msg) {
        case WM_TIMER:
            if (wParam == TIMER_SPIN) {
                presenter.onSpinnerTick(hwnd);
                return 0;
            }
            break;
        case WM_PAINT:
            presenter.paintSpinner(hwnd);
            return 0;
        case WM_ERASEBKGND:
            return 1;
        default:
            break;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

static LRESULT CALLBACK StandaloneProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_SIZE:
            Core::instance().presenter().onStandaloneResized();
            return 0;
        case WM_ERASEBKGND: {
            // The window shows before the WebView2 controller exists: paint the sheet colour
            // until the webview covers the client area, never a blank or stale surface.
            uint32_t argb = Core::instance().presenter().sheetArgb();
            HDC dc = reinterpret_cast<HDC>(wParam);
            RECT client;
            GetClientRect(hwnd, &client);
            HBRUSH brush = CreateSolidBrush(RGB((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF));
            FillRect(dc, &client, brush);
            DeleteObject(brush);
            return 1;
        }
        case WM_CLOSE:
            // The session decides; teardown destroys the window when it agrees.
            Core::instance().requestUserDismiss();
            return 0;
        case WM_KEYDOWN:
            if (wParam == VK_ESCAPE) {
                Core::instance().requestUserDismiss();
                return 0;
            }
            break;
        default:
            break;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

// -- Presenter ------------------------------------------------------------------------------

Presenter::Presenter(Core &core) : core_(core) {}

Presenter::~Presenter() {}

void Presenter::registerClasses() {
    if (classesRegistered_) {
        return;
    }
    struct ClassSpec {
        const wchar_t *name;
        WNDPROC proc;
        UINT style;
    };
    const ClassSpec classes[] = {
        {kClassBackdrop, BackdropProc, 0},
        {kClassCard, CardProc, CS_HREDRAW | CS_VREDRAW},
        {kClassSpinner, SpinnerProc, 0},
        {kClassStandalone, StandaloneProc, CS_HREDRAW | CS_VREDRAW},
    };
    for (const ClassSpec &spec : classes) {
        WNDCLASSEXW wc = {};
        wc.cbSize = sizeof(wc);
        wc.style = spec.style;
        wc.lpfnWndProc = spec.proc;
        wc.hInstance = core_.moduleInstance();
        wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        wc.lpszClassName = spec.name;
        RegisterClassExW(&wc);
    }
    classesRegistered_ = true;
}

bool Presenter::isLive() const {
    if (!live_ || hidden_) {
        return false;
    }
    HWND window = standalone_ != nullptr ? standalone_ : host_;
    return window == nullptr || IsWindow(window);
}

HWND Presenter::dialogOwner() const {
    return standalone_ != nullptr ? standalone_ : host_;
}

HWND Presenter::webViewParent() const {
    return card_ != nullptr ? card_ : standalone_;
}

Presenter::Metrics Presenter::computeMetrics() const {
    Metrics m = {};
    GetClientRect(host_, &m.client);
    m.scale = dpiScale(host_);
    double clientW = m.client.right - m.client.left;
    double clientH = m.client.bottom - m.client.top;
    SurfaceSize size = resolveSurfaceSize(config_, clientW / m.scale, clientH / m.scale);
    int w = static_cast<int>(std::floor(size.width * m.scale));
    int h = static_cast<int>(std::floor(size.height * m.scale));
    int x = static_cast<int>((clientW - w) / 2);
    int y = static_cast<int>((clientH - h) / 2);
    m.card = {x, y, x + w, y + h};
    m.headerHeight = static_cast<int>(kHeaderHeightPt * m.scale);
    return m;
}

RECT Presenter::webViewBounds() const {
    RECT rc = {};
    if (standalone_ != nullptr) {
        GetClientRect(standalone_, &rc);
        return rc;
    }
    if (card_ != nullptr) {
        GetClientRect(card_, &rc);
        rc.top = static_cast<int>(kHeaderHeightPt * dpiScale(card_));
    }
    return rc;
}

// The layered backdrop composites over its siblings' GDI output regardless of z-order, so the
// card's rect is cut out of it: the card is never dimmed and never occluded.
void Presenter::applyBackdropRegion(const Metrics &m) {
    if (backdrop_ == nullptr || card_ == nullptr) {
        return;
    }
    int clientW = m.client.right - m.client.left;
    int clientH = m.client.bottom - m.client.top;
    int radius = static_cast<int>(kCornerRadiusPt * m.scale);
    HRGN region = CreateRectRgn(0, 0, clientW, clientH);
    HRGN hole = CreateRoundRectRgn(m.card.left, m.card.top, m.card.right + 1, m.card.bottom + 1, radius, radius);
    CombineRgn(region, region, hole, RGN_DIFF);
    DeleteObject(hole);
    SetWindowRgn(backdrop_, region, TRUE);
}

bool Presenter::presentAttached(HWND host, const SurfaceConfig &config, uint32_t sheetArgb) {
    teardown();
    if (host == nullptr || !IsWindow(host)) {
        return false;
    }
    registerClasses();
    host_ = host;
    config_ = config;
    sheetArgb_ = sheetArgb;
    dark_ = theme::isDarkColor(sheetArgb);
    hidden_ = false;

    // Child overlays need the host to clip them out of its own drawing. Only the one bit is
    // added, and only that bit is removed again: the game may change its style meanwhile.
    LONG_PTR style = GetWindowLongPtrW(host_, GWL_STYLE);
    if ((style & WS_CLIPCHILDREN) == 0) {
        SetWindowLongPtrW(host_, GWL_STYLE, style | WS_CLIPCHILDREN);
        hostStyleModified_ = true;
    }

    Metrics m = computeMetrics();
    int clientW = m.client.right - m.client.left;
    int clientH = m.client.bottom - m.client.top;
    HINSTANCE module = core_.moduleInstance();

    backdrop_ = CreateWindowExW(WS_EX_LAYERED, kClassBackdrop, L"", WS_CHILD | WS_VISIBLE, 0, 0, clientW, clientH,
                                host_, nullptr, module, nullptr);
    backdropAlpha_ = 0;
    SetLayeredWindowAttributes(backdrop_, 0, 0, LWA_ALPHA);
    SetTimer(backdrop_, TIMER_FADE, 16, nullptr);
    SetTimer(backdrop_, TIMER_LAYOUT, 250, nullptr);

    int w = m.card.right - m.card.left;
    int h = m.card.bottom - m.card.top;
    int radius = static_cast<int>(kCornerRadiusPt * m.scale);
    card_ = CreateWindowExW(0, kClassCard, L"", WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN, m.card.left, m.card.top, w, h,
                            host_, nullptr, module, nullptr);
    SetWindowRgn(card_, CreateRoundRectRgn(0, 0, w + 1, h + 1, radius, radius), TRUE);

    bool dismissable = config.mode != SurfaceMode::Modal || config.allowDismiss;
    if (dismissable) {
        int btn = static_cast<int>(kCloseButtonPt * m.scale);
        closeButton_ = CreateWindowExW(0, L"BUTTON", L"", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
                                       w - btn - static_cast<int>(8 * m.scale), (m.headerHeight - btn) / 2, btn, btn, card_,
                                       reinterpret_cast<HMENU>(static_cast<INT_PTR>(kIdCloseButton)), module, nullptr);
    }

    int spin = static_cast<int>(kSpinnerSizePt * m.scale);
    spinner_ = CreateWindowExW(0, kClassSpinner, L"", WS_CHILD, (w - spin) / 2, m.headerHeight + (h - m.headerHeight - spin) / 2,
                               spin, spin, card_, nullptr, module, nullptr);

    // Dim only what is behind the card: beneath it in z-order and cut out of the backdrop.
    SetWindowPos(backdrop_, card_, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    applyBackdropRegion(m);
    lastClientWidth_ = clientW;
    lastClientHeight_ = clientH;
    lastCard_ = m.card;
    live_ = true;
    // Keyboard input belongs to the checkout from this moment, not once the asynchronous
    // WebView2 controller has been created and moved focus; the game's focus comes back on hide.
    previousFocus_ = GetFocus();
    SetFocus(card_);
    setLoading(true);
    return true;
}

void Presenter::presentStandalone(const SurfaceConfig &config, uint32_t sheetArgb) {
    teardown();
    registerClasses();
    config_ = config;
    sheetArgb_ = sheetArgb;
    dark_ = theme::isDarkColor(sheetArgb);
    hidden_ = false;

    double scale = dpiScale(nullptr);
    SurfaceSize size = resolveSurfaceSize(config, 0, 0);
    RECT frame = {0, 0, static_cast<int>(size.width * scale), static_cast<int>(size.height * scale)};
    AdjustWindowRect(&frame, WS_OVERLAPPEDWINDOW, FALSE);
    int fw = frame.right - frame.left;
    int fh = frame.bottom - frame.top;
    int x = (GetSystemMetrics(SM_CXSCREEN) - fw) / 2;
    int y = (GetSystemMetrics(SM_CYSCREEN) - fh) / 2;
    standalone_ = CreateWindowExW(0, kClassStandalone, L"Stash Checkout", WS_OVERLAPPEDWINDOW, x, y, fw, fh, nullptr, nullptr,
                                  core_.moduleInstance(), nullptr);
    ShowWindow(standalone_, SW_SHOW);
    SetForegroundWindow(standalone_);

    RECT client;
    GetClientRect(standalone_, &client);
    int spin = static_cast<int>(kSpinnerSizePt * scale);
    spinner_ = CreateWindowExW(0, kClassSpinner, L"", WS_CHILD, (client.right - spin) / 2, (client.bottom - spin) / 2, spin, spin,
                               standalone_, nullptr, core_.moduleInstance(), nullptr);
    live_ = true;
    setLoading(true);
}

void Presenter::updateTrustHeader(const std::string &url) {
    headerScheme_ = url::scheme(url);
    headerHost_ = url::host(url);
    if (card_ != nullptr) {
        InvalidateRect(card_, nullptr, FALSE);
    }
    if (standalone_ != nullptr) {
        std::string title = headerScheme_ == "file" ? std::string("Local checkout (file)")
                            : !headerHost_.empty()  ? headerHost_
                                                    : std::string("Stash Checkout");
        SetWindowTextW(standalone_, widen(title).c_str());
    }
}

void Presenter::setLoading(bool loading) {
    if (spinner_ == nullptr) {
        return;
    }
    if (loading) {
        ShowWindow(spinner_, SW_SHOWNA);
        SetTimer(spinner_, TIMER_SPIN, 33, nullptr);
    } else {
        KillTimer(spinner_, TIMER_SPIN);
        ShowWindow(spinner_, SW_HIDE);
    }
}

// Host-resize tracking. Recomputes the card from the live client rect and re-cuts the backdrop;
// the caller re-applies the WebView2 bounds when the card rect changed (the exclusive-to-
// borderless switch changes size and DPI at once, which is where the header used to vanish).
bool Presenter::layout() {
    if (!live_ || hidden_ || host_ == nullptr || card_ == nullptr) {
        return false;
    }
    if (!IsWindow(host_)) {
        // Game window is gone (app closing): drop the surface silently.
        core_.resetPresentationState();
        return false;
    }
    Metrics m = computeMetrics();
    int clientW = m.client.right - m.client.left;
    int clientH = m.client.bottom - m.client.top;
    webview::applyBounds();
    if (clientW == lastClientWidth_ && clientH == lastClientHeight_ && EqualRect(&m.card, &lastCard_)) {
        return false;
    }
    lastClientWidth_ = clientW;
    lastClientHeight_ = clientH;
    lastCard_ = m.card;

    MoveWindow(backdrop_, 0, 0, clientW, clientH, TRUE);
    int w = m.card.right - m.card.left;
    int h = m.card.bottom - m.card.top;
    int radius = static_cast<int>(kCornerRadiusPt * m.scale);
    MoveWindow(card_, m.card.left, m.card.top, w, h, TRUE);
    SetWindowRgn(card_, CreateRoundRectRgn(0, 0, w + 1, h + 1, radius, radius), TRUE);
    if (closeButton_ != nullptr) {
        int btn = static_cast<int>(kCloseButtonPt * m.scale);
        MoveWindow(closeButton_, w - btn - static_cast<int>(8 * m.scale), (m.headerHeight - btn) / 2, btn, btn, TRUE);
    }
    if (spinner_ != nullptr) {
        int spin = static_cast<int>(kSpinnerSizePt * m.scale);
        MoveWindow(spinner_, (w - spin) / 2, m.headerHeight + (h - m.headerHeight - spin) / 2, spin, spin, TRUE);
    }
    applyBackdropRegion(m);
    InvalidateRect(card_, nullptr, TRUE);
    return true;
}

void Presenter::onStandaloneResized() {
    if (standalone_ == nullptr) {
        return;
    }
    RECT client;
    GetClientRect(standalone_, &client);
    if (spinner_ != nullptr) {
        int spin = static_cast<int>(kSpinnerSizePt * dpiScale(standalone_));
        MoveWindow(spinner_, (client.right - spin) / 2, (client.bottom - spin) / 2, spin, spin, TRUE);
    }
    webview::applyBounds();
}

void Presenter::hide() {
    // Idempotent: closeSurface hides at once and the deferred teardown hides again; the focus
    // restored by the first call must not be moved a second time.
    if (!live_ || hidden_) {
        return;
    }
    hidden_ = true;
    if (backdrop_ != nullptr) {
        KillTimer(backdrop_, TIMER_LAYOUT);
        KillTimer(backdrop_, TIMER_FADE);
        ShowWindow(backdrop_, SW_HIDE);
    }
    if (spinner_ != nullptr) {
        KillTimer(spinner_, TIMER_SPIN);
    }
    if (card_ != nullptr) {
        ShowWindow(card_, SW_HIDE);
    }
    if (standalone_ != nullptr) {
        ShowWindow(standalone_, SW_HIDE);
    }
    // Give focus (and keyboard input) back to whatever had it before the overlay, else the host.
    HWND focusTarget = (previousFocus_ != nullptr && IsWindow(previousFocus_)) ? previousFocus_ : host_;
    previousFocus_ = nullptr;
    if (focusTarget != nullptr && IsWindow(focusTarget)) {
        SetFocus(focusTarget);
    }
    if (host_ != nullptr && IsWindow(host_)) {
        InvalidateRect(host_, nullptr, TRUE);
    }
}

void Presenter::destroyWindows() {
    destroying_ = true;
    if (spinner_ != nullptr) {
        KillTimer(spinner_, TIMER_SPIN);
        DestroyWindow(spinner_);
        spinner_ = nullptr;
    }
    if (closeButton_ != nullptr) {
        DestroyWindow(closeButton_);
        closeButton_ = nullptr;
    }
    if (card_ != nullptr) {
        DestroyWindow(card_);
        card_ = nullptr;
    }
    if (backdrop_ != nullptr) {
        KillTimer(backdrop_, TIMER_LAYOUT);
        KillTimer(backdrop_, TIMER_FADE);
        DestroyWindow(backdrop_);
        backdrop_ = nullptr;
    }
    if (standalone_ != nullptr) {
        DestroyWindow(standalone_);
        standalone_ = nullptr;
    }
    destroying_ = false;
}

void Presenter::teardown() {
    if (!live_) {
        return;
    }
    hide();
    destroyWindows();
    if (host_ != nullptr && hostStyleModified_ && IsWindow(host_)) {
        LONG_PTR style = GetWindowLongPtrW(host_, GWL_STYLE);
        SetWindowLongPtrW(host_, GWL_STYLE, style & ~static_cast<LONG_PTR>(WS_CLIPCHILDREN));
    }
    hostStyleModified_ = false;
    host_ = nullptr;
    previousFocus_ = nullptr;
    live_ = false;
    hidden_ = false;
    headerHost_.clear();
    headerScheme_.clear();
}

// -- Painting -------------------------------------------------------------------------------

void Presenter::onFadeTick(HWND hwnd) {
    backdropAlpha_ += 20;
    if (backdropAlpha_ >= kBackdropTargetAlpha) {
        backdropAlpha_ = kBackdropTargetAlpha;
        KillTimer(hwnd, TIMER_FADE);
    }
    SetLayeredWindowAttributes(hwnd, 0, static_cast<BYTE>(backdropAlpha_), LWA_ALPHA);
}

void Presenter::onSpinnerTick(HWND hwnd) {
    spinnerAngle_ = (spinnerAngle_ + 18) % 360;
    InvalidateRect(hwnd, nullptr, FALSE);
    // The WebView2 widget window appears asynchronously on top of its siblings; keep the
    // spinner visible until the page loads.
    SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

// Lock glyph drawn with GDI so it renders identically everywhere; the row is native chrome.
void Presenter::drawTrustHeader(HDC dc, int width, int headerHeight, double scale) {
    COLORREF sheet = colorFromArgb(sheetArgb_);
    COLORREF headerBg = blend(sheet, dark_ ? RGB(255, 255, 255) : RGB(0, 0, 0), dark_ ? 0.07 : 0.05);
    COLORREF text = dark_ ? RGB(190, 196, 206) : RGB(80, 84, 92);
    COLORREF lockGreen = RGB(74, 222, 128);

    RECT header = {0, 0, width, headerHeight};
    HBRUSH bg = CreateSolidBrush(headerBg);
    FillRect(dc, &header, bg);
    DeleteObject(bg);

    int pad = static_cast<int>(14 * scale);
    int lockW = 0;
    if (headerScheme_ == "https") {
        int bodyW = static_cast<int>(10 * scale);
        int bodyH = static_cast<int>(7 * scale);
        int cx = pad + bodyW / 2;
        int bodyTop = headerHeight / 2;
        HBRUSH lockBrush = CreateSolidBrush(lockGreen);
        HPEN lockPen = CreatePen(PS_SOLID, static_cast<int>(1.6 * scale) < 1 ? 1 : static_cast<int>(1.6 * scale), lockGreen);
        HGDIOBJ oldBrush = SelectObject(dc, lockBrush);
        HGDIOBJ oldPen = SelectObject(dc, GetStockObject(NULL_PEN));
        RoundRect(dc, pad, bodyTop, pad + bodyW, bodyTop + bodyH, static_cast<int>(3 * scale), static_cast<int>(3 * scale));
        SelectObject(dc, lockPen);
        SelectObject(dc, GetStockObject(NULL_BRUSH));
        int shackle = static_cast<int>(3 * scale);
        Arc(dc, cx - shackle, bodyTop - shackle * 2, cx + shackle, bodyTop + shackle, cx + shackle, bodyTop, cx - shackle, bodyTop);
        SelectObject(dc, oldBrush);
        SelectObject(dc, oldPen);
        DeleteObject(lockBrush);
        DeleteObject(lockPen);
        lockW = bodyW + static_cast<int>(7 * scale);
    }

    std::string label;
    if (headerScheme_ == "file") {
        label = "Local checkout (file)";
    } else if (!headerHost_.empty()) {
        label = headerHost_;
    }
    HFONT font = CreateFontW(-static_cast<int>(12 * scale), 0, 0, 0, FW_MEDIUM, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                             OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    HGDIOBJ oldFont = SelectObject(dc, font);
    SetTextColor(dc, text);
    SetBkMode(dc, TRANSPARENT);
    RECT textRect = {pad + lockW, 0, width - static_cast<int>(48 * scale), headerHeight};
    std::wstring wide = widen(label);
    DrawTextW(dc, wide.c_str(), -1, &textRect, DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
    SelectObject(dc, oldFont);
    DeleteObject(font);
}

void Presenter::paintCard(HWND hwnd) {
    PAINTSTRUCT ps;
    HDC dc = BeginPaint(hwnd, &ps);
    RECT rc;
    GetClientRect(hwnd, &rc);
    HBRUSH bg = CreateSolidBrush(colorFromArgb(sheetArgb_));
    FillRect(dc, &rc, bg);
    DeleteObject(bg);
    double scale = dpiScale(hwnd);
    drawTrustHeader(dc, rc.right - rc.left, static_cast<int>(kHeaderHeightPt * scale), scale);
    EndPaint(hwnd, &ps);
}

void Presenter::drawCloseButton(const DRAWITEMSTRUCT *item) {
    COLORREF sheet = colorFromArgb(sheetArgb_);
    bool pressed = (item->itemState & ODS_SELECTED) != 0;
    COLORREF bg = blend(sheet, dark_ ? RGB(255, 255, 255) : RGB(0, 0, 0), pressed ? 0.22 : 0.12);
    COLORREF fg = dark_ ? RGB(220, 224, 230) : RGB(60, 64, 72);
    HBRUSH brush = CreateSolidBrush(bg);
    FillRect(item->hDC, &item->rcItem, brush);
    DeleteObject(brush);
    // An X from two strokes, no glyph font dependency.
    double scale = dpiScale(item->hwndItem);
    int inset = static_cast<int>(8 * scale);
    HPEN pen = CreatePen(PS_SOLID, static_cast<int>(1.5 * scale) < 1 ? 1 : static_cast<int>(1.5 * scale), fg);
    HGDIOBJ oldPen = SelectObject(item->hDC, pen);
    MoveToEx(item->hDC, item->rcItem.left + inset, item->rcItem.top + inset, nullptr);
    LineTo(item->hDC, item->rcItem.right - inset, item->rcItem.bottom - inset);
    MoveToEx(item->hDC, item->rcItem.right - inset, item->rcItem.top + inset, nullptr);
    LineTo(item->hDC, item->rcItem.left + inset, item->rcItem.bottom - inset);
    SelectObject(item->hDC, oldPen);
    DeleteObject(pen);
}

void Presenter::paintSpinner(HWND hwnd) {
    PAINTSTRUCT ps;
    HDC dc = BeginPaint(hwnd, &ps);
    RECT rc;
    GetClientRect(hwnd, &rc);
    HBRUSH bg = CreateSolidBrush(colorFromArgb(sheetArgb_));
    FillRect(dc, &rc, bg);
    DeleteObject(bg);
    int cx = (rc.right - rc.left) / 2;
    int cy = (rc.bottom - rc.top) / 2;
    int radius = (cx < cy ? cx : cy) - 4;
    double scale = dpiScale(hwnd);
    int penWidth = static_cast<int>(3 * scale) < 2 ? 2 : static_cast<int>(3 * scale);
    HPEN pen = CreatePen(PS_SOLID, penWidth, dark_ ? RGB(255, 255, 255) : RGB(64, 64, 64));
    HGDIOBJ oldPen = SelectObject(dc, pen);
    SelectObject(dc, GetStockObject(NULL_BRUSH));
    double a0 = spinnerAngle_ * 3.14159265 / 180.0;
    double a1 = a0 + 4.7;
    Arc(dc, cx - radius, cy - radius, cx + radius, cy + radius, cx + static_cast<int>(radius * std::cos(a1)),
        cy - static_cast<int>(radius * std::sin(a1)), cx + static_cast<int>(radius * std::cos(a0)),
        cy - static_cast<int>(radius * std::sin(a0)));
    SelectObject(dc, oldPen);
    DeleteObject(pen);
    EndPaint(hwnd, &ps);
}

}  // namespace win
}  // namespace desktop
}  // namespace stash
