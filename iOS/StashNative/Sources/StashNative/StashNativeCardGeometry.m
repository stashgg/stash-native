#import "StashNativePrivate.h"
#import <math.h>

CGRect StashChooseAvailableRegion(CGRect bounds, NSArray<NSValue *> *regions, CGPoint preferredPoint, BOOL rightToLeft) {
    NSMutableArray<NSValue *> *panes = [NSMutableArray arrayWithObject:[NSValue valueWithCGRect:bounds]];
    for (NSValue *value in regions) {
        CGRect obstacle = value.CGRectValue;
        NSMutableArray<NSValue *> *next = [NSMutableArray array];
        for (NSValue *pane in panes) {
            CGRect rect = pane.CGRectValue;
            CGRect overlap = CGRectIntersection(rect, obstacle);
            if (CGRectIsNull(overlap) || CGRectIsEmpty(overlap)) { [next addObject:pane]; continue; }
            CGRect candidates[] = {
                CGRectMake(rect.origin.x, rect.origin.y, overlap.origin.x - rect.origin.x, rect.size.height),
                CGRectMake(CGRectGetMaxX(overlap), rect.origin.y, CGRectGetMaxX(rect) - CGRectGetMaxX(overlap), rect.size.height),
                CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, overlap.origin.y - rect.origin.y),
                CGRectMake(rect.origin.x, CGRectGetMaxY(overlap), rect.size.width, CGRectGetMaxY(rect) - CGRectGetMaxY(overlap))
            };
            for (NSUInteger i = 0; i < 4; i++) {
                if (candidates[i].size.width > 0 && candidates[i].size.height > 0) {
                    [next addObject:[NSValue valueWithCGRect:candidates[i]]];
                }
            }
        }
        panes = next;
    }
    CGRect best = CGRectZero;
    BOOL bestContains = NO;
    for (NSValue *value in panes) {
        CGRect candidate = value.CGRectValue;
        BOOL contains = CGRectContainsPoint(candidate, preferredPoint);
        CGFloat area = candidate.size.width * candidate.size.height;
        CGFloat bestArea = best.size.width * best.size.height;
        BOOL tie = fabs(area - bestArea) < 0.5;
        if ((contains && !bestContains) || (contains == bestContains &&
            (area > bestArea || (tie && (CGRectGetMaxY(candidate) > CGRectGetMaxY(best) ||
             (CGRectGetMaxY(candidate) == CGRectGetMaxY(best) && (rightToLeft ? CGRectGetMinX(candidate) < CGRectGetMinX(best) : CGRectGetMaxX(candidate) > CGRectGetMaxX(best)))))))) {
            best = candidate;
            bestContains = contains;
        }
    }
    return best;
}

CGRect StashChooseBottomAttachedRegion(CGRect bounds, NSArray<NSValue *> *regions) {
    CGFloat top = CGRectGetMinY(bounds);
    for (NSValue *value in regions) {
        CGRect overlap = CGRectIntersection(bounds, value.CGRectValue);
        if (!CGRectIsNull(overlap) && !CGRectIsEmpty(overlap)) top = MAX(top, CGRectGetMaxY(overlap));
    }
    return CGRectMake(bounds.origin.x, top, MAX(0, bounds.size.width), MAX(0, CGRectGetMaxY(bounds) - top));
}

StashPresentationGeometry StashResolveGeometry(CGRect bounds, StashNativeCardConfig *config, BOOL expanded) {
    CGFloat width = MAX(0, bounds.size.width), height = MAX(0, bounds.size.height);
    BOOL centered = width >= 600;
    CGFloat margin = MIN(config.edgeMargin, MIN(width, height) / 4);
    CGFloat maxHeight = MAX(0, height - (centered ? 2 : 1) * margin);
    if (config.maximumContentHeight > 0) maxHeight = MIN(maxHeight, config.maximumContentHeight);
    CGFloat resting = MIN(config.preferredContentHeight, maxHeight);
    CGFloat contentHeight = expanded ? maxHeight : resting;
    CGFloat surfaceWidth = centered ? MIN(config.preferredContentWidth, MAX(0, width - 2 * margin)) : width;
    CGFloat surfaceHeight = MIN(height, contentHeight);
    CGRect frame = CGRectMake(CGRectGetMidX(bounds) - surfaceWidth / 2,
        centered ? CGRectGetMidY(bounds) - surfaceHeight / 2 : CGRectGetMaxY(bounds) - surfaceHeight,
        surfaceWidth, surfaceHeight);
    return (StashPresentationGeometry){frame, resting, maxHeight, centered};
}
