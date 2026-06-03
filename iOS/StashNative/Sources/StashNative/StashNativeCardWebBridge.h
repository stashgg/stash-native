//
//  StashNativeCardWebBridge.h
//  StashNative
//
//  window.stash_sdk message-name constants, defined in StashNativeCardWebBridge.m. Core references
//  these to build the injected stashSDKScript and to register/remove the WKScriptMessage handlers.
//  These string values are the externally-observable JS channel names -- keep them byte-identical
//  and mirrored with Android (StashWebViewUtils.JS_SDK_SCRIPT) and docs/stash-sdk-js.md.
//

#import <Foundation/Foundation.h>

extern NSString * const kMessageHandlerPaymentSuccess;
extern NSString * const kMessageHandlerPaymentFailure;
extern NSString * const kMessageHandlerPurchaseProcessing;
extern NSString * const kMessageHandlerOptin;
extern NSString * const kMessageHandlerExpand;
extern NSString * const kMessageHandlerCollapse;
extern NSString * const kMessageHandlerWindowClose;
extern NSString * const kMessageHandlerExternalPayment;
extern NSString * const kMessageHandlerPageReady;
