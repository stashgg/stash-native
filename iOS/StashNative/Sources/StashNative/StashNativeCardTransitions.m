#import "StashNativeCardPrivate.h"
#import <math.h>
#import <string.h>

static NSString *const StashEntranceCorrectionKey = @"StashCenteredEntrance";

static BOOL StashAnimationPoint(id value, CGPoint *point) {
    if (![value isKindOfClass:NSValue.class] || strcmp([value objCType], @encode(CGPoint))) return NO;
    *point = [value CGPointValue];
    return isfinite(point->x) && isfinite(point->y);
}

static BOOL StashScaleCompensation(CAAnimation *candidate, CALayer *layer, CALayer *container) {
    if (![candidate isKindOfClass:CASpringAnimation.class]) return NO;
    CASpringAnimation *animation = (CASpringAnimation *)candidate;
    CGPoint from, to;
    if (![animation.keyPath isEqualToString:@"position"] || !animation.additive || animation.cumulative ||
        animation.autoreverses || animation.repeatCount != 0 || animation.repeatDuration != 0 ||
        animation.byValue || animation.valueFunction || !isfinite(animation.beginTime) || animation.beginTime < 0 ||
        !isfinite(animation.duration) || animation.duration <= 0 ||
        !isfinite(animation.speed) || animation.speed <= 0 || !isfinite(animation.timeOffset) ||
        !isfinite(animation.mass) || animation.mass <= 0 ||
        !isfinite(animation.stiffness) || animation.stiffness <= 0 ||
        !isfinite(animation.damping) || animation.damping < 0 || !isfinite(animation.initialVelocity) ||
        !StashAnimationPoint(animation.fromValue, &from) || !StashAnimationPoint(animation.toValue, &to) ||
        fabs(to.x) > 0.000001 || fabs(to.y) > 0.000001) return NO;
    CATransform3D transform = layer.transform;
    if (!CATransform3DIsAffine(transform) || !isfinite(transform.m11) || !isfinite(transform.m22) ||
        !isfinite(transform.m12) || !isfinite(transform.m21) ||
        !isfinite(transform.m41) || !isfinite(transform.m42) ||
        fabs(transform.m12) > 0.000001 || fabs(transform.m21) > 0.000001 ||
        fabs(transform.m11 - transform.m22) > 0.000001 || transform.m11 <= 0 || transform.m11 >= 1 ||
        !isfinite(layer.anchorPoint.x) || !isfinite(layer.anchorPoint.y) ||
        fabs(layer.anchorPoint.x - 0.5) > 0.000001 || fabs(layer.anchorPoint.y - 0.5) > 0.000001) return NO;
    CGSize size = layer.bounds.size;
    if (!isfinite(size.width) || !isfinite(size.height) || size.width <= 0 || size.height <= 0) return NO;
    CGFloat x = size.width * (1 - transform.m11) / 2;
    CGFloat y = size.height * (1 - transform.m22) / 2;
    CGRect frame = [layer convertRect:layer.bounds toLayer:container];
    return x > 0.5 && fabs(from.x + x) < 0.01 && fabs(from.y + y) < 0.01 &&
        isfinite(CGRectGetMidX(frame)) && isfinite(CGRectGetMidY(frame)) &&
        isfinite(CGRectGetMidX(container.bounds)) &&
        fabs(CGRectGetMidX(frame) - CGRectGetMidX(container.bounds)) < 0.5;
}

static BOOL StashSameEntranceAnimation(CAAnimation *candidate, CASpringAnimation *original) {
    if (![candidate isKindOfClass:CASpringAnimation.class]) return NO;
    CASpringAnimation *animation = (CASpringAnimation *)candidate;
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
    if (@available(iOS 17.0, *)) {
        if (animation.allowsOverdamping != original.allowsOverdamping) return NO;
    }
#endif
    return animation.class == original.class && [animation.keyPath isEqualToString:original.keyPath] &&
        [animation.fromValue isEqual:original.fromValue] && [animation.toValue isEqual:original.toValue] &&
        animation.byValue == nil && animation.valueFunction == nil &&
        animation.beginTime == original.beginTime && animation.duration == original.duration &&
        animation.speed == original.speed && animation.timeOffset == original.timeOffset &&
        animation.mass == original.mass && animation.stiffness == original.stiffness &&
        animation.damping == original.damping && animation.initialVelocity == original.initialVelocity &&
        animation.additive == original.additive && animation.cumulative == original.cumulative &&
        animation.autoreverses == original.autoreverses && animation.repeatCount == original.repeatCount &&
        animation.repeatDuration == original.repeatDuration &&
        animation.removedOnCompletion == original.removedOnCompletion &&
        [animation.fillMode isEqualToString:original.fillMode] &&
        (animation.timingFunction == original.timingFunction || [animation.timingFunction isEqual:original.timingFunction]);
}

@interface StashNativeEntranceCorrection ()
@property (nonatomic, strong) CALayer *layer;
@property (nonatomic, copy) NSString *sourceKey;
@property (nonatomic, copy) CASpringAnimation *sourceAnimation;
@end

@implementation StashNativeEntranceCorrection
+ (instancetype)correctionForSurface:(CALayer *)surface container:(CALayer *)container {
    if (!surface || !container || surface == container) return nil;
    CALayer *ancestor = surface;
    NSMutableArray<CALayer *> *layers = [NSMutableArray array];
    while (ancestor && ancestor != container && layers.count < 16) {
        [layers addObject:ancestor]; ancestor = ancestor.superlayer;
    }
    if (ancestor != container) return nil;
    CALayer *match = nil;
    NSString *matchKey = nil;
    CASpringAnimation *source = nil;
    // UIKit may group the animated surface in a layer without adding a UIView.
    for (CALayer *layer in layers) {
        for (NSString *key in layer.animationKeys) {
            if ([key isEqualToString:StashEntranceCorrectionKey]) continue;
            CAAnimation *candidate = [layer animationForKey:key];
            if (!StashScaleCompensation(candidate, layer, container)) continue;
            if (match) return nil;
            match = layer; matchKey = key; source = (CASpringAnimation *)candidate;
        }
    }
    if (!match || [match animationForKey:StashEntranceCorrectionKey]) return nil;
    StashNativeEntranceCorrection *correction = [[self alloc] init];
    correction.layer = match; correction.sourceKey = matchKey; correction.sourceAnimation = source;
    // Cancel only horizontal scale compensation, on the same native animation clock.
    // Keep UIKit's original spring and its completion delegate untouched.
    CASpringAnimation *counter = [source copy];
    counter.fromValue = [NSValue valueWithCGPoint:CGPointMake(-[source.fromValue CGPointValue].x, 0)];
    counter.toValue = [NSValue valueWithCGPoint:CGPointZero];
    counter.delegate = nil;
    [match addAnimation:counter forKey:StashEntranceCorrectionKey];
#if !__has_feature(objc_arc)
    [counter release];
    return [correction autorelease];
#else
    return correction;
#endif
}
- (void)update {
    CASpringAnimation *source = (CASpringAnimation *)[self.layer animationForKey:self.sourceKey];
    CAAnimation *counter = [self.layer animationForKey:StashEntranceCorrectionKey];
    // Both implicit start times resolve together in their first transaction commit.
    if (self.sourceAnimation.beginTime == 0 && source.beginTime > 0 && counter.beginTime == source.beginTime)
        self.sourceAnimation.beginTime = source.beginTime;
    // Keep equal and opposite contributions paired even if the parent geometry changes.
    if (!counter || !StashSameEntranceAnimation(source, self.sourceAnimation))
        [self invalidate];
}
- (void)invalidate {
    [self.layer removeAnimationForKey:StashEntranceCorrectionKey];
    self.layer = nil; self.sourceKey = nil; self.sourceAnimation = nil;
}
- (void)dealloc {
    [_layer removeAnimationForKey:StashEntranceCorrectionKey];
#if !__has_feature(objc_arc)
    [_layer release]; [_sourceKey release]; [_sourceAnimation release];
    [super dealloc];
#endif
}
@end
