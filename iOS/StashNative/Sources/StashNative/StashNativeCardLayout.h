//
//  StashNativeCardLayout.h
//  StashNative
//
//  Card view-layout utilities: WebView frame/scroll configuration, drag-tray and handle
//  layout, and background color. No file-scope state.
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

/// Switches the card's WebView from Auto Layout to frame-based layout. Returns the WebView.
WKWebView *stash_switchWebViewToFrameLayoutInCardView(UIView *cardView);

/// Lays out the card's WebView (and tray) to fill cardView.bounds.
void stash_layoutCardContentToBounds(UIView *cardView);

/// Updates the drag tray and handle bar frame inside cardView.
void stash_updateDragTrayAndHandleInCardView(UIView *cardView, CGFloat cardWidth);

/// Applies bounce/overscroll limits to the WKWebView's scroll view.
void stash_configureScrollViewForWebView(UIScrollView *scrollView);

/// Sets the WebView (and its scroll view) background color.
void stash_setWebViewBackgroundColor(WKWebView *webView, UIColor *color);
