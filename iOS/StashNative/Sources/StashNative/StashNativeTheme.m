//
//  StashNativeTheme.m
//  StashNative
//
//  Checkout theme selection.
//

#import "StashNative.h"
#import "StashNativePrivate.h"
#import <UIKit/UIKit.h>

// Non-ARC compatibility: These warnings are suppressed when compiling without ARC
// (e.g., in game engines like Unreal Engine that manage memory manually).
// ARC builds do not need these suppressions.
#if !__has_feature(objc_arc)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshadow"
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

#pragma mark - Theme (query parameter)

static NSString * const kThemeQueryParamName = @"theme";
static NSString * const kThemeLight = @"light";
static NSString * const kThemeDark = @"dark";

UIColor* StashSystemBackgroundColor(UITraitCollection *traits) {
    traits = traits ?: UITraitCollection.currentTraitCollection;
    return traits.userInterfaceStyle == UIUserInterfaceStyleDark
        ? [UIColor colorWithRed:0x1e/255.0 green:0x1e/255.0 blue:0x1e/255.0 alpha:1.0]
        : [UIColor.systemBackgroundColor resolvedColorWithTraitCollection:traits];
}

BOOL StashEffectiveThemeIsDark(UITraitCollection *traits) {
    traits = traits ?: UITraitCollection.currentTraitCollection;
    return traits.userInterfaceStyle == UIUserInterfaceStyleDark;
}

UIColor* StashSheetBackgroundUIColor(UITraitCollection *traits) {
    return StashSystemBackgroundColor(traits);
}

NSInteger StashGlassLoadingOverride = -1;

BOOL StashGlassLoadingAvailable(void) {
    if (StashGlassLoadingOverride >= 0) return StashGlassLoadingOverride == 1;
    // iPadOS 26.1 accepts a detent background effect but draws nothing, leaving a transparent card.
    // Earlier systems load behind an opaque cover in the sheet color.
    if (@available(iOS 27.0, *)) return YES;
    return NO;
}

NSString* StashAppendThemeQueryParameter(NSString* url, UITraitCollection *traits) {
    if (url == nil || url.length == 0) {
        return url;
    }

    NSString *theme = StashEffectiveThemeIsDark(traits) ? kThemeDark : kThemeLight;

    NSURLComponents *components = [NSURLComponents componentsWithString:url];
    if (components == nil) {
        NSString *separator = [url containsString:@"?"] ? @"&" : @"?";
        return [NSString stringWithFormat:@"%@%@%@=%@", url, separator, kThemeQueryParamName, theme];
    }
    
    // Filter and append on percentEncodedQuery, never queryItems: the decode/re-encode
    // round-trip turns %2B into a literal plus (read back as a space server-side),
    // corrupting signed or base64 checkout parameters. Android does the same string-level
    // filtering in stripThemeQueryParameter.
    NSString *existingQuery = components.percentEncodedQuery;
    NSMutableArray *keptPairs = [NSMutableArray array];
    if (existingQuery.length > 0) {
        for (NSString *pair in [existingQuery componentsSeparatedByString:@"&"]) {
            if (pair.length == 0) {
                continue;
            }
            NSString *name = [pair componentsSeparatedByString:@"="].firstObject;
            if (![name isEqualToString:kThemeQueryParamName]) {
                [keptPairs addObject:pair];
            }
        }
    }
    [keptPairs addObject:[NSString stringWithFormat:@"%@=%@", kThemeQueryParamName, theme]];
    components.percentEncodedQuery = [keptPairs componentsJoinedByString:@"&"];

    return components.URL.absoluteString;
}

#if !__has_feature(objc_arc)
#pragma clang diagnostic pop
#endif
