//
//  StashNativeCardLayout.h
//  StashNative
//
//  Stateless card view-layout utilities: WebView frame/scroll configuration, drag-tray and handle
//  layout, and background color. No file-scope state. The sizing-ratio frame geometry stays in
//  StashNativeCard.m (it reads the configuration statics).
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

/// Switches the card's WebView from Auto Layout to frame-based layout; call before animating the
/// card frame (e.g. rotation) so the WebView resizes with the card.
WKWebView *stash_switchWebViewToFrameLayoutInCardView(UIView *cardView);

/// Lays out the card's WebView (and tray) to fill cardView.bounds; call after rotation or any card
/// frame change so the WebView resizes correctly.
void stash_layoutCardContentToBounds(UIView *cardView);

/// Updates the drag tray and handle bar frame inside cardView (used by iPad transition and
/// expand/collapse).
void stash_updateDragTrayAndHandleInCardView(UIView *cardView, CGFloat cardWidth);

/// Applies bounce/overscroll limits to the WKWebView's scroll view; call after creation and on
/// navigation (WebKit may reset scroll properties).
void stash_configureScrollViewForWebView(UIScrollView *scrollView);

/// Sets the WebView (and its scroll view) background color.
void stash_setWebViewBackgroundColor(WKWebView *webView, UIColor *color);
