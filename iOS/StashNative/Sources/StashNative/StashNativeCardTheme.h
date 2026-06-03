//
//  StashNativeCardTheme.h
//  StashNative
//
//  Sheet theming helpers (light/dark decision + sheet background color + the dark-sheet document
//  JavaScript), shared by the presentation/webview code. The caller's optional background-color hex
//  is held by the file-scope stash_presentationBackgroundColorHex in StashNativeCard.m; these
//  functions read it. Implementations live in StashNativeCardTheme.m.
//

#import <UIKit/UIKit.h>

/// Parses a #RGB/#RRGGBB(AA) string to a UIColor, or nil if malformed/empty.
UIColor *stash_parseHTMLHexColor(NSString *hex);

/// YES if the color's sRGB luminance is dark enough to warrant a dark sheet/web theme.
BOOL stash_colorIsDarkBackground(UIColor *color);

/// YES when the sheet should use the dark theme: from the caller background color if set, else the
/// system trait collection.
BOOL stash_effectiveThemeIsDark(void);

/// `#RRGGBB` string for a UIColor (falls back to the dark surface hex if components are unavailable).
NSString *stash_cssHexFromUIColor(UIColor *color);

/// The resolved sheet background color: the caller color if valid, else the system background color.
UIColor *stash_sheetBackgroundUIColor(void);

/// YES when the checkout WebView should use the dark `theme=` / color-scheme.
BOOL StashNativeSheetUsesDarkWebTheme(void);

/// Document-end JavaScript that paints html/body background + color-scheme to match the dark sheet.
NSString *StashNativeDarkSheetBackgroundJavaScript(void);
