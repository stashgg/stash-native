//
//  StashNativeCardTheme.m
//  StashNative
//
//  Sheet theming: parses the optional caller background-color hex, decides light/dark (sRGB
//  luminance or the system trait collection), and produces the sheet UIColor + the document-end
//  JavaScript that paints the page background to match. The chosen background color is applied to
//  the card/modal chrome and mirrored into the WebView so there is no white flash. Moved verbatim
//  from StashNativeCard.m.
//

#import "StashNativeCard.h"
#import "StashNativeCardPrivate.h"
#import "StashNativeCardTheme.h"

#if !__has_feature(objc_arc)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshadow"
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

static double stash_srgbLinearize(double c) {
    return (c <= 0.03928) ? (c / 12.92) : pow((c + 0.055) / 1.055, 2.4);
}

BOOL stash_colorIsDarkBackground(UIColor *color) {
    if (!color) {
        return YES;
    }
    CGFloat r, g, b, a;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w;
        if (![color getWhite:&w alpha:&a]) {
            return YES;
        }
        r = g = b = w;
    }
    double lum = 0.2126 * stash_srgbLinearize(r) + 0.7152 * stash_srgbLinearize(g) + 0.0722 * stash_srgbLinearize(b);
    return lum < 0.5;
}

UIColor *stash_parseHTMLHexColor(NSString *hex) {
    if (hex.length == 0) {
        return nil;
    }
    NSString *s = [[hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (s.length == 0) {
        return nil;
    }
    if ([s hasPrefix:@"#"]) {
        s = [s substringFromIndex:1];
    }
    unsigned r = 0, g = 0, b = 0, a = 255;
    if (s.length == 3) {
        for (NSInteger i = 0; i < 3; i++) {
            unichar ch = [s characterAtIndex:i];
            int v = 0;
            if (ch >= '0' && ch <= '9') {
                v = (int)(ch - '0');
            } else if (ch >= 'a' && ch <= 'f') {
                v = (int)(ch - 'a' + 10);
            } else {
                return nil;
            }
            v = v * 16 + v;
            if (i == 0) {
                r = (unsigned)v;
            } else if (i == 1) {
                g = (unsigned)v;
            } else {
                b = (unsigned)v;
            }
        }
    } else if (s.length == 6) {
        unsigned value = 0;
        NSScanner *scanner = [NSScanner scannerWithString:s];
        if (![scanner scanHexInt:&value] || value > 0xFFFFFF) {
            return nil;
        }
        r = (value >> 16) & 0xFF;
        g = (value >> 8) & 0xFF;
        b = value & 0xFF;
    } else if (s.length == 8) {
        char buf[9] = {0};
        if (![s getCString:buf maxLength:sizeof(buf) encoding:NSUTF8StringEncoding]) {
            return nil;
        }
        char *end = NULL;
        unsigned long value = strtoul(buf, &end, 16);
        if (end != buf + 8 || value > 0xFFFFFFFFUL) {
            return nil;
        }
        a = (unsigned)((value >> 24) & 0xFF);
        r = (unsigned)((value >> 16) & 0xFF);
        g = (unsigned)((value >> 8) & 0xFF);
        b = (unsigned)(value & 0xFF);
    } else {
        return nil;
    }
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:a / 255.0];
}

BOOL stash_effectiveThemeIsDark(void) {
    if (stash_presentationBackgroundColorHex.length > 0) {
        UIColor *c = stash_parseHTMLHexColor(stash_presentationBackgroundColorHex);
        if (c) {
            return stash_colorIsDarkBackground(c);
        }
    }
    if (@available(iOS 13.0, *)) {
        return [UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return NO;
}

NSString *stash_cssHexFromUIColor(UIColor *color) {
    CGFloat r, g, b, a;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w;
        if (![color getWhite:&w alpha:&a]) {
            return @"#1e1e1e";
        }
        r = g = b = w;
    }
    return [NSString stringWithFormat:@"#%02lX%02lX%02lX",
            (unsigned long)lround(r * 255.0),
            (unsigned long)lround(g * 255.0),
            (unsigned long)lround(b * 255.0)];
}

UIColor* stash_sheetBackgroundUIColor(void) {
    if (stash_presentationBackgroundColorHex.length > 0) {
        UIColor *parsed = stash_parseHTMLHexColor(stash_presentationBackgroundColorHex);
        if (parsed) {
            return parsed;
        }
    }
    return stash_getSystemBackgroundColor();
}

BOOL StashNativeSheetUsesDarkWebTheme(void) {
    return stash_effectiveThemeIsDark();
}

NSString *StashNativeDarkSheetBackgroundJavaScript(void) {
    NSString *hex = stash_cssHexFromUIColor(stash_sheetBackgroundUIColor());
    return [NSString stringWithFormat:
        @"(function(){try{var BG='%@';var h=document.head;if(h&&!h.querySelector('meta[name=color-scheme]')){var m=document.createElement('meta');m.setAttribute('name','color-scheme');m.setAttribute('content','dark');h.insertBefore(m,h.firstChild);}var e=document.documentElement;if(e){e.style.setProperty('background-color',BG,'important');e.style.setProperty('color-scheme','dark','important');}var b=document.body;if(b){b.style.setProperty('background-color',BG,'important');b.style.setProperty('color-scheme','dark','important');}}catch(x){}})();",
        hex];
}

#if !__has_feature(objc_arc)
#pragma clang diagnostic pop
#endif
