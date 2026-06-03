//
//  StashNativeCardWebBridge.h
//  StashNative
//
//  window.stash_sdk message-handler name constants, defined in StashNativeCardWebBridge.m.
//  Each string value is a WKScriptMessage handler name.
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
