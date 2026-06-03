//
//  StashNativeCardConfigs.m
//  StashNative
//
//  Implementations of the public configuration value types: StashNativeCardConfig (card sizing +
//  forcePortrait/autoClose/background), StashNativeModalConfig (modal sizing + allowDismiss), and
//  StashNativePopupSizeConfig (popup multipliers). Their public @interfaces live in
//  include/StashNativeCard.h. Initializers set the default values. Pure value objects with no SDK
//  state.
//

#import "StashNativeCard.h"
#import "StashNativeCardPrivate.h"

#if !__has_feature(objc_arc)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshadow"
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

#pragma mark - PopupSizeConfig Implementation

@implementation StashNativePopupSizeConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _portraitWidthMultiplier = kPopupPortraitWidthMultiplier;
        _portraitHeightMultiplier = kPopupPortraitHeightMultiplier;
        _landscapeWidthMultiplier = kPopupLandscapeWidthMultiplier;
        _landscapeHeightMultiplier = kPopupLandscapeHeightMultiplier;
    }
    return self;
}

- (instancetype)initWithPortraitWidth:(CGFloat)portraitWidth
                       portraitHeight:(CGFloat)portraitHeight
                       landscapeWidth:(CGFloat)landscapeWidth
                      landscapeHeight:(CGFloat)landscapeHeight {
    self = [super init];
    if (self) {
        _portraitWidthMultiplier = portraitWidth;
        _portraitHeightMultiplier = portraitHeight;
        _landscapeWidthMultiplier = landscapeWidth;
        _landscapeHeightMultiplier = landscapeHeight;
    }
    return self;
}

@end

#pragma mark - ModalConfig Implementation

@implementation StashNativeModalConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _phoneWidthRatioPortrait = 0.80f;
        _phoneHeightRatioPortrait = 0.50f;
        _phoneWidthRatioLandscape = 0.50f;
        _phoneHeightRatioLandscape = 0.80f;
        _tabletWidthRatioPortrait = 0.40f;
        _tabletHeightRatioPortrait = 0.30f;
        _tabletWidthRatioLandscape = 0.30f;
        _tabletHeightRatioLandscape = 0.40f;
        _allowDismiss = YES;
        _autoClose = YES;
        _backgroundColor = nil;
    }
    return self;
}

- (instancetype)initWithPhoneWidthPortrait:(CGFloat)phoneWidthPortrait
                         phoneHeightPortrait:(CGFloat)phoneHeightPortrait
                         phoneWidthLandscape:(CGFloat)phoneWidthLandscape
                        phoneHeightLandscape:(CGFloat)phoneHeightLandscape
                        tabletWidthPortrait:(CGFloat)tabletWidthPortrait
                       tabletHeightPortrait:(CGFloat)tabletHeightPortrait
                       tabletWidthLandscape:(CGFloat)tabletWidthLandscape
                      tabletHeightLandscape:(CGFloat)tabletHeightLandscape
                              allowDismiss:(BOOL)allowDismiss {
    self = [super init];
    if (self) {
        _phoneWidthRatioPortrait = phoneWidthPortrait;
        _phoneHeightRatioPortrait = phoneHeightPortrait;
        _phoneWidthRatioLandscape = phoneWidthLandscape;
        _phoneHeightRatioLandscape = phoneHeightLandscape;
        _tabletWidthRatioPortrait = tabletWidthPortrait;
        _tabletHeightRatioPortrait = tabletHeightPortrait;
        _tabletWidthRatioLandscape = tabletWidthLandscape;
        _tabletHeightRatioLandscape = tabletHeightLandscape;
        _allowDismiss = allowDismiss;
        _autoClose = YES;
        _backgroundColor = nil;
    }
    return self;
}

@end

#pragma mark - CardConfig Implementation

@implementation StashNativeCardConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _forcePortrait = NO;
        _cardHeightRatioPortrait = 0.68f;
        _cardWidthRatioLandscape = 0.7f;
        _cardHeightRatioLandscape = 0.9f;
        _tabletWidthRatioPortrait = 0.4f;
        _tabletHeightRatioPortrait = 0.5f;
        _tabletWidthRatioLandscape = 0.3f;
        _tabletHeightRatioLandscape = 0.6f;
        _autoClose = YES;
        _backgroundColor = nil;
    }
    return self;
}

@end

#if !__has_feature(objc_arc)
#pragma clang diagnostic pop
#endif
