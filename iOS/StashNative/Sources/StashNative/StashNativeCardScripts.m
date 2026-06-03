//
//  StashNativeCardScripts.m
//  StashNative
//
//  JS source strings injected into the WebView, including the window.stash_sdk bridge surface.
//

#import "StashNativeCardScripts.h"
#import "StashNativeCardWebBridge.h"

NSString *stash_viewportUserScriptSource(void) {
    return @"var meta = document.createElement('meta'); \
        meta.name = 'viewport'; \
        meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover'; \
        document.head.appendChild(meta);";
}

// window.stash_sdk bridge JavaScript.
NSString *stash_bridgeUserScriptSource(void) {
    return [NSString stringWithFormat:@"(function() {"
        "window.stash_sdk = window.stash_sdk || {};"
        "window.stash_sdk.onPaymentSuccess = function(order) {"
            "var payload = '';"
            "if (arguments.length > 0 && order !== undefined && order !== null) {"
            "  payload = (typeof order === 'string') ? order : JSON.stringify(order);"
            "}"
            "window.webkit.messageHandlers.%@.postMessage(payload);"
        "};"
        "window.stash_sdk.onPaymentFailure = function(data) {"
            "window.webkit.messageHandlers.%@.postMessage(data || {});"
        "};"
        "window.stash_sdk.onPurchaseProcessing = function(data) {"
            "window.webkit.messageHandlers.%@.postMessage(data || {});"
        "};"
        "window.stash_sdk.setPaymentChannel = function(optinType) {"
            "window.webkit.messageHandlers.%@.postMessage(optinType || '');"
        "};"
        "window.stash_sdk.expand = function() {"
            "window.webkit.messageHandlers.%@.postMessage({});"
        "};"
        "window.stash_sdk.collapse = function() {"
            "window.webkit.messageHandlers.%@.postMessage({});"
        "};"
        "window.stash_sdk.openExternalBrowser = function(url) {"
            "var s = (url !== undefined && url !== null) ? String(url) : '';"
            "window.webkit.messageHandlers.%@.postMessage(s);"
        "};"
        "try { window.close = function() {"
            "try { window.webkit.messageHandlers.%@.postMessage({}); } catch(e2) {}"
        "}; } catch(e) {}"
    "})();",
        kMessageHandlerPaymentSuccess, kMessageHandlerPaymentFailure, kMessageHandlerPurchaseProcessing,
        kMessageHandlerOptin, kMessageHandlerExpand, kMessageHandlerCollapse, kMessageHandlerExternalPayment,
        kMessageHandlerWindowClose];
}

NSString *stash_noMarginsUserScriptSource(void) {
    return @"var style = document.createElement('style'); \
        style.innerHTML = 'body { margin: 0 !important; padding: 0 !important; min-height: 100% !important; } \
        html { margin: 0 !important; padding: 0 !important; height: 100% !important; }'; \
        document.head.appendChild(style);";
}

NSString *stash_darkBackgroundAtStartUserScriptSource(NSString *cssHexColor) {
    return [NSString stringWithFormat:
                @"(function(){"
                "var BG='%@';"
                @"function paint(){try{var e=document.documentElement;if(e){e.style.setProperty('background-color',BG,'important');e.style.setProperty('color-scheme','dark','important');}var b=document.body;if(b){b.style.setProperty('background-color',BG,'important');b.style.setProperty('color-scheme','dark','important');}}catch(x){}}"
                @"paint();"
                @"document.addEventListener('readystatechange',function(){if(document.readyState==='interactive'||document.readyState==='complete')paint();});"
                @"document.addEventListener('DOMContentLoaded',paint);"
                @"})();", cssHexColor];
}

NSString *stash_pageReadyUserScriptSource(void) {
    return [NSString stringWithFormat:
            @"(function(){"
            @"if(window.__stashNativeRevealInit)return;"
            @"window.__stashNativeRevealInit=1;"
            @"var H='%@';"
            @"function ok(){"
            @"try{"
            @"if(document.readyState==='loading')return false;"
            @"if(!document.documentElement)return false;"
            @"if(window.getComputedStyle(document.documentElement).display==='none')return false;"
            @"if(!document.body)return false;"
            @"if(window.getComputedStyle(document.body).display==='none')return false;"
            @"}catch(e){return false;}"
            @"return true;"
            @"}"
            @"function send(){"
            @"if(window.__stashNativePageReadySent)return;"
            @"if(!ok())return;"
            @"window.__stashNativePageReadySent=1;"
            @"requestAnimationFrame(function(){requestAnimationFrame(function(){"
            @"try{window.webkit.messageHandlers[H].postMessage({});}catch(e){}"
            @"});});"
            @"}"
            @"document.addEventListener('readystatechange',send);"
            @"window.addEventListener('load',send,{once:true});"
            @"send();"
            @"})();",
            kMessageHandlerPageReady];
}
