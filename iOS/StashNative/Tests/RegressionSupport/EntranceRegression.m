#import "RegressionSupport.h"
#import "../../Sources/StashNative/StashNativeCardPrivate.h"

static NSString *const StashProbeCounterKey = @"StashCenteredEntrance";

@interface StashEntranceFixture : NSObject
@property (nonatomic, strong) CALayer *container;
@property (nonatomic, strong) CALayer *wrapper;
@property (nonatomic, strong) CALayer *surface;
@property (nonatomic, strong) CASpringAnimation *source;
- (void)installSource;
@end

@implementation StashEntranceFixture
- (instancetype)init {
    if ((self = [super init])) {
        self.container = [CALayer layer];
        self.container.bounds = CGRectMake(0, 0, 402, 874);
        self.wrapper = [CALayer layer];
        self.wrapper.bounds = CGRectMake(0, 0, 402, 594);
        self.wrapper.position = CGPointMake(201, 580);
        self.wrapper.transform = CATransform3DMakeScale(386.0 / 402, 386.0 / 402, 1);
        [self.container addSublayer:self.wrapper];
        self.surface = [CALayer layer];
        [self.wrapper addSublayer:self.surface];
        self.source = [CASpringAnimation animationWithKeyPath:@"position"];
        self.source.fromValue = [NSValue valueWithCGPoint:CGPointMake(-8, -594.0 * 8 / 402)];
        self.source.toValue = [NSValue valueWithCGPoint:CGPointZero];
        self.source.additive = YES;
        self.source.duration = 0.5;
        self.source.mass = 2;
        self.source.stiffness = 300;
        self.source.damping = 30;
        self.source.initialVelocity = 1;
        self.source.removedOnCompletion = NO;
        self.source.fillMode = kCAFillModeBoth;
        [self installSource];
    }
    return self;
}
- (void)installSource { [self.wrapper addAnimation:self.source forKey:@"source"]; }
@end

NSDictionary *StashNativeEntranceProbe(void) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSNumber *start in @[@0, @123.25]) {
        StashEntranceFixture *fixture = [StashEntranceFixture new];
        fixture.source.beginTime = start.doubleValue;
        [fixture installSource];
        CASpringAnimation *vertical = [fixture.source copy];
        vertical.fromValue = [NSValue valueWithCGPoint:CGPointMake(0, 594)];
        [fixture.wrapper addAnimation:vertical forKey:@"vertical"];
        StashNativeEntranceCorrection *correction = [StashNativeEntranceCorrection
            correctionForSurface:fixture.surface container:fixture.container];
        CASpringAnimation *counter = (CASpringAnimation *)[fixture.wrapper animationForKey:StashProbeCounterKey];
        CASpringAnimation *source = (CASpringAnimation *)[fixture.wrapper animationForKey:@"source"];
        BOOL matched = correction && counter && counter.class == source.class &&
            CGPointEqualToPoint([counter.fromValue CGPointValue], CGPointMake(8, 0)) &&
            CGPointEqualToPoint([counter.toValue CGPointValue], CGPointZero) && counter.additive && !counter.delegate &&
            counter.beginTime == source.beginTime && counter.duration == source.duration &&
            counter.mass == source.mass && counter.stiffness == source.stiffness &&
            counter.damping == source.damping && counter.initialVelocity == source.initialVelocity &&
            counter.removedOnCompletion == source.removedOnCompletion && [counter.fillMode isEqual:source.fillMode] &&
            [source.fromValue isEqual:fixture.source.fromValue] &&
            [[fixture.wrapper animationForKey:@"vertical"] isKindOfClass:CASpringAnimation.class];
        [correction update];
        matched &= [fixture.wrapper animationForKey:StashProbeCounterKey] != nil;
        // Parent geometry cannot break equal and opposite contributions on the same layer.
        fixture.container.transform = CATransform3DMakeRotation(0.2, 0, 0, 1);
        [correction update];
        matched &= [fixture.wrapper animationForKey:StashProbeCounterKey] != nil;
        [correction invalidate]; [correction invalidate];
        matched &= ![fixture.wrapper animationForKey:StashProbeCounterKey] &&
            [fixture.wrapper animationForKey:@"source"] != nil;
        result[start.doubleValue == 0 ? @"implicitClock" : @"explicitClock"] = @(matched);
    }
    for (NSString *name in @[@"missingSource", @"retimedSource", @"replacedSource", @"implicitPromotion"]) {
        StashEntranceFixture *fixture = [StashEntranceFixture new];
        StashNativeEntranceCorrection *correction = [StashNativeEntranceCorrection
            correctionForSurface:fixture.surface container:fixture.container];
        if ([name isEqual:@"missingSource"]) [fixture.wrapper removeAnimationForKey:@"source"];
        if ([name isEqual:@"retimedSource"]) { fixture.source.speed = 0.5; [fixture installSource]; }
        if ([name isEqual:@"replacedSource"]) {
            [fixture.wrapper addAnimation:[CABasicAnimation animationWithKeyPath:@"opacity"] forKey:@"source"];
        }
        BOOL promotion = [name isEqual:@"implicitPromotion"];
        if (promotion) {
            fixture.source.beginTime = 123.25; [fixture installSource];
            CASpringAnimation *counter = [[fixture.wrapper animationForKey:StashProbeCounterKey] copy];
            counter.beginTime = fixture.source.beginTime;
            [fixture.wrapper addAnimation:counter forKey:StashProbeCounterKey];
        }
        [correction update];
        result[name] = @(correction && ([fixture.wrapper animationForKey:StashProbeCounterKey] != nil) == promotion);
        [correction invalidate];
    }
    for (NSString *name in @[@"ambiguous", @"wrongContainer", @"noInset", @"rotation", @"nonuniformScale",
        @"wrongAnchor", @"wrongOffset", @"wrongEndpoint", @"nonadditive", @"repeating", @"wrongValueType"]) {
        StashEntranceFixture *fixture = [StashEntranceFixture new];
        if ([name isEqual:@"ambiguous"]) [fixture.wrapper addAnimation:fixture.source forKey:@"another"];
        if ([name isEqual:@"wrongContainer"]) fixture.container = [CALayer layer];
        if ([name isEqual:@"noInset"]) fixture.wrapper.transform = CATransform3DIdentity;
        if ([name isEqual:@"rotation"]) fixture.wrapper.transform = CATransform3DRotate(fixture.wrapper.transform, 0.1, 0, 0, 1);
        if ([name isEqual:@"nonuniformScale"]) fixture.wrapper.transform = CATransform3DMakeScale(386.0 / 402, 0.9, 1);
        if ([name isEqual:@"wrongAnchor"]) fixture.wrapper.anchorPoint = CGPointZero;
        if ([name isEqual:@"wrongOffset"]) fixture.source.fromValue = [NSValue valueWithCGPoint:CGPointMake(-7, -10)];
        if ([name isEqual:@"wrongEndpoint"]) fixture.source.toValue = [NSValue valueWithCGPoint:CGPointMake(1, 0)];
        if ([name isEqual:@"nonadditive"]) fixture.source.additive = NO;
        if ([name isEqual:@"repeating"]) fixture.source.repeatCount = 2;
        if ([name isEqual:@"wrongValueType"]) fixture.source.fromValue = @8;
        [fixture installSource];
        StashNativeEntranceCorrection *correction = [StashNativeEntranceCorrection
            correctionForSurface:fixture.surface container:fixture.container];
        result[name] = @(!correction && ![fixture.wrapper animationForKey:StashProbeCounterKey]);
        [correction invalidate];
    }
    return result;
}
