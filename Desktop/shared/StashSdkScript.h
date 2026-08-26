// window.stash_sdk shim for the desktop hosts. Mirror of the 2.3.0 mobile script
// (Android StashWebViewUtils.JS_SDK_SCRIPT, iOS stashSDKScript in StashNativeCard.m); spec of
// record is docs/stash-sdk-js.md. Changes here MUST be mirrored on mobile and documented there.
//
// One body, one per-OS transport prelude: WKWebView posts to window.webkit.messageHandlers[name],
// WebView2 posts {type, data} to window.chrome.webview. Every bridge call is wrapped in try/catch
// (the Android shape). The script only runs in the top document: WKUserScript is added
// forMainFrameOnly, WebView2 runs document-created scripts in every frame, so the guard is
// in the script itself.
#ifndef STASH_SDK_SCRIPT_H
#define STASH_SDK_SCRIPT_H

// Message names shared by the shim and both hosts' dispatch.
#define STASH_SDK_MSG_PAYMENT_SUCCESS      "stashPaymentSuccess"
#define STASH_SDK_MSG_PAYMENT_FAILURE      "stashPaymentFailure"
#define STASH_SDK_MSG_PURCHASE_PROCESSING  "stashPurchaseProcessing"
#define STASH_SDK_MSG_PROCESSING_COMPLETED "stashProcessingCompleted"
#define STASH_SDK_MSG_OPTIN                "stashOptin"
#define STASH_SDK_MSG_EXPAND               "stashExpand"
#define STASH_SDK_MSG_COLLAPSE             "stashCollapse"
#define STASH_SDK_MSG_EXTERNAL_PAYMENT     "stashExternalPayment"
#define STASH_SDK_MSG_OPEN_LINK            "stashOpenLink"
#define STASH_SDK_MSG_WINDOW_CLOSE         "stashWindowClose"

#define STASH_SDK_SCRIPT_PRELUDE_WEBKIT \
    "var post=function(n,d){window.webkit.messageHandlers[n].postMessage(d);};"
#define STASH_SDK_SCRIPT_PRELUDE_WEBVIEW2 \
    "var post=function(n,d){window.chrome.webview.postMessage({type:n,data:d});};"

// Body: identical to the mobile scripts modulo the transport. onPaymentSuccess passes strings
// through, JSON.stringify-s objects, and sends '' when the argument is missing / null.
#define STASH_SDK_SCRIPT_BODY \
    "window.stash_sdk = window.stash_sdk || {};" \
    "window.stash_sdk.onPaymentSuccess = function(order) {" \
    "  try { var p = '';" \
    "    if (arguments.length > 0 && order !== undefined && order !== null) {" \
    "      p = (typeof order === 'string') ? order : JSON.stringify(order);" \
    "    }" \
    "    post('" STASH_SDK_MSG_PAYMENT_SUCCESS "', p); } catch(e) {}" \
    "};" \
    "window.stash_sdk.onPaymentFailure = function(data) {" \
    "  try { post('" STASH_SDK_MSG_PAYMENT_FAILURE "', data || {}); } catch(e) {}" \
    "};" \
    "window.stash_sdk.onPurchaseProcessing = function(data) {" \
    "  try { post('" STASH_SDK_MSG_PURCHASE_PROCESSING "', data || {}); } catch(e) {}" \
    "};" \
    "window.stash_sdk.onProcessingCompleted = function(data) {" \
    "  try { post('" STASH_SDK_MSG_PROCESSING_COMPLETED "', data || {}); } catch(e) {}" \
    "};" \
    "window.stash_sdk.setPaymentChannel = function(optinType) {" \
    "  try { post('" STASH_SDK_MSG_OPTIN "', optinType || ''); } catch(e) {}" \
    "};" \
    "window.stash_sdk.expand = function() {" \
    "  try { post('" STASH_SDK_MSG_EXPAND "', {}); } catch(e) {}" \
    "};" \
    "window.stash_sdk.collapse = function() {" \
    "  try { post('" STASH_SDK_MSG_COLLAPSE "', {}); } catch(e) {}" \
    "};" \
    "window.stash_sdk.openExternalBrowser = function(url) {" \
    "  try { post('" STASH_SDK_MSG_EXTERNAL_PAYMENT "', (url !== undefined && url !== null) ? String(url) : ''); } catch(e) {}" \
    "};" \
    "window.stash_sdk.openLink = function(url) {" \
    "  try { post('" STASH_SDK_MSG_OPEN_LINK "', (url !== undefined && url !== null) ? String(url) : ''); } catch(e) {}" \
    "};" \
    "try { window.close = function() { try { post('" STASH_SDK_MSG_WINDOW_CLOSE "', {}); } catch(e2) {} }; } catch(e) {}"

#define STASH_SDK_SCRIPT_WITH_PRELUDE(prelude) \
    "(function() {" \
    "if (window !== window.top) return;" \
    prelude \
    STASH_SDK_SCRIPT_BODY \
    "})();"

#define STASH_SDK_SCRIPT_WEBKIT   STASH_SDK_SCRIPT_WITH_PRELUDE(STASH_SDK_SCRIPT_PRELUDE_WEBKIT)
#define STASH_SDK_SCRIPT_WEBVIEW2 STASH_SDK_SCRIPT_WITH_PRELUDE(STASH_SDK_SCRIPT_PRELUDE_WEBVIEW2)

// Dark sheet: pins html/body to the sheet colour and color-scheme like iOS (StashNativeCardTheme.m).
// %s-free on purpose: hosts splice the hex in with StashDesktopTheme::darkSheetScript().
#define STASH_SDK_DARK_SHEET_SCRIPT_PREFIX \
    "(function(){var BG='"
#define STASH_SDK_DARK_SHEET_SCRIPT_SUFFIX \
    "';" \
    "function paint(){try{" \
    "var e=document.documentElement;if(e){e.style.setProperty('background-color',BG,'important');e.style.setProperty('color-scheme','dark','important');}" \
    "var b=document.body;if(b){b.style.setProperty('background-color',BG,'important');b.style.setProperty('color-scheme','dark','important');}" \
    "var h=document.head;if(h&&!h.querySelector('meta[name=color-scheme]')){var m=document.createElement('meta');m.setAttribute('name','color-scheme');m.setAttribute('content','dark');h.insertBefore(m,h.firstChild);}" \
    "}catch(x){}}" \
    "paint();" \
    "document.addEventListener('readystatechange',function(){if(document.readyState==='interactive'||document.readyState==='complete')paint();});" \
    "document.addEventListener('DOMContentLoaded',paint);" \
    "})();"

#endif
