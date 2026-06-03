//
//  StashNativeCardScripts.h
//  StashNative
//
//  Builders for the JavaScript injected into the checkout WKWebView. Pure string
//  sources -- no file-scope state; the WKUserScript/addUserScript plumbing and the
//  document-start/end injection-time choices stay with the WebView setup in
//  StashNativeCard.m. The companion document-end dark painter is
//  StashNativeDarkSheetBackgroundJavaScript() in StashNativeCardTheme.m.
//

#import <Foundation/Foundation.h>

/// Viewport <meta> (device-width, no user scaling, viewport-fit=cover). Injected at document end.
NSString *stash_viewportUserScriptSource(void);

/// The window.stash_sdk bridge. CANONICAL surface: keep byte-identical and mirrored with Android
/// (StashWebViewUtils.JS_SDK_SCRIPT) and docs/stash-sdk-js.md. The channel-name string values come
/// from the kMessageHandler* constants (StashNativeCardWebBridge). Injected at document start.
NSString *stash_bridgeUserScriptSource(void);

/// Zeroes html/body margin + padding so the sheet fills the card. Injected at document start.
NSString *stash_noMarginsUserScriptSource(void);

/// Paints html/body background + color-scheme to the given CSS hex for the dark sheet, re-applying
/// as the document becomes ready. Injected at document start. cssHexColor is `#RRGGBB`.
NSString *stash_darkBackgroundAtStartUserScriptSource(NSString *cssHexColor);

/// Reveal hook: posts the page-ready channel once the document is laid out (readystate / load + rAF).
/// Idempotent. Injected at document end.
NSString *stash_pageReadyUserScriptSource(void);
