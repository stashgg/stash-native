#import "StashNativeCardPrivate.h"
#import <math.h>

@implementation StashNativeCardConfig
- (instancetype)init {
    if ((self = [super init])) {
        _preferredContentWidth = 400;
        _preferredContentHeight = 560;
        _maximumContentHeight = 720;
        _edgeMargin = 16;
        _allowDismiss = YES;
        _autoClose = YES;
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone {
    StashNativeCardConfig *copy = [[[self class] allocWithZone:zone] init];
    copy.preferredContentWidth = self.preferredContentWidth;
    copy.preferredContentHeight = self.preferredContentHeight;
    copy.maximumContentHeight = self.maximumContentHeight;
    copy.edgeMargin = self.edgeMargin;
    copy.allowDismiss = self.allowDismiss;
    copy.autoClose = self.autoClose;
    copy.orientationPreference = self.orientationPreference;
    return copy;
}
@end

CGFloat StashFinitePositive(CGFloat value, CGFloat fallback) {
    return isfinite(value) && value > 0 ? value : fallback;
}

StashNativeCardConfig *StashNormalizedConfig(StashNativeCardConfig *config) {
    StashNativeCardConfig *result = config ? [config copy] : [[StashNativeCardConfig alloc] init];
    result.preferredContentWidth = StashFinitePositive(result.preferredContentWidth, 400);
    result.preferredContentHeight = StashFinitePositive(result.preferredContentHeight, 560);
    if (!isfinite(result.maximumContentHeight) || result.maximumContentHeight < 0) {
        result.maximumContentHeight = 720;
    }
    if (!isfinite(result.edgeMargin) || result.edgeMargin < 0) result.edgeMargin = 16;
    if (result.orientationPreference != StashNativeOrientationPreferencePortrait) {
        result.orientationPreference = StashNativeOrientationPreferenceFollowHost;
    }
#if !__has_feature(objc_arc)
    return [result autorelease];
#else
    return result;
#endif
}
