//
//  DZScrollingInspector.m
//  TSMiniWebBrowserDemo
//
//  Created by Denis Zamataev on 9/2/13.
//
//

#import "DZScrollingInspector.h"

@implementation DZScrollingInspector

@synthesize limits = _limits;

- (id)initWithObservedScrollView:(UIScrollView *)scrollView
                andOffsetKeyPath:(NSString *)offsetKeyPath
                 andInsetKeypath:(NSString *)insetKeyPath
                 andTargetObject:(NSObject *)target
   andTargetFramePropertyKeyPath:(NSString *)keypath
                       andLimits:(DZScrollingInspectorTwoOrientationsLimits)limits
{
    if (self = [super init])
    {
        // defaults
        _scrollDirection = DZScrollDirectionNone;
        _lastScrollDirectionThatWasntNone = DZScrollDirectionNone;
        _isSuspended = NO;
        _isAnimatingTargetObject = NO;
        
        // arguments to properties
        _scrollView = scrollView;
        _targetObject = target;
        _targetFramePropertyKeyPath = keypath;
        _limits = limits;
        _offsetKeypath = offsetKeyPath;
        _insetKeypath = insetKeyPath;
        
        // get more parameters from target
        _offset = [DZScrollingInspector contentOffsetValueForKey:offsetKeyPath fromObject:scrollView];
        _inset = [DZScrollingInspector contentInsetValueForKey:insetKeyPath fromObject:scrollView];
        
        _targetFramePropertyInitialValue = [self getTargetCurrentValueForKeypath];
        
        [self registerAsObserver];
    }
    return self;
}

// Apple documentation about the observing https://developer.apple.com/library/ios/DOCUMENTATION/Cocoa/Conceptual/KeyValueObserving/Articles/KVOBasics.html
- (void)registerAsObserver {
    /*
     Register self to receive change notifications for the "_keypath_" property of
     the 'scrollView' object and specify that both the old and new values of "_keypath_"
     should be provided in the observe… method.
     */
    [_scrollView addObserver:self
                  forKeyPath: DZScrollingInspector_CONTENT_OFFSET_KEYPATH
                 options:(NSKeyValueObservingOptionNew |
                          NSKeyValueObservingOptionOld)
                 context:NULL];
    
    [_scrollView addObserver:self
                  forKeyPath: DZScrollingInspector_CONTENT_INSET_KEYPATH
                     options:(NSKeyValueObservingOptionNew |
                              NSKeyValueObservingOptionOld)
                     context:NULL];
    
    [_scrollView addObserver:self
                  forKeyPath: DZScrollingInspector_IS_DRAGGING_KEYPATH
                     options:(NSKeyValueObservingOptionNew |
                              NSKeyValueObservingOptionOld)
                     context:NULL];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    
    CGFloat offset = 0.0f;
    CGFloat inset = 0.0f;
    
    BOOL offsetChanged = NO;
    BOOL insetChanged = NO;
    
    if ([keyPath isEqual:DZScrollingInspector_CONTENT_OFFSET_KEYPATH]) {
        NSValue *newValue = [change objectForKey:NSKeyValueChangeNewKey];
        offset = [DZScrollingInspector contentOffsetValueForKey:_offsetKeypath fromCGPoint:newValue.CGPointValue];
        NSLog(@"new offset %f", offset);
        
        offsetChanged = YES;
    }
    
    
    if ([keyPath isEqual:DZScrollingInspector_CONTENT_INSET_KEYPATH]) {
        NSValue *newValue = [change objectForKey:NSKeyValueChangeNewKey];
        inset = newValue.UIEdgeInsetsValue.top;
        NSLog(@"new inset %f", inset);
        
        insetChanged = YES;
    }
    
    if ([keyPath isEqual:DZScrollingInspector_CONTENT_INSET_KEYPATH]) {
        NSNumber *newValue = [change objectForKey:NSKeyValueChangeNewKey];
        inset = newValue.UIEdgeInsetsValue.top;
        NSLog(@"new isDragging %f", inset);
        
        insetChanged = YES;
    }
    
    
    if (offsetChanged) {
        inset = _inset;
    }
    if (insetChanged) {
        offset = _offset;
    }
    
    [self assumeScrollDirection:offset andInset:inset];
    
    if (_scrollView.isDragging && !_isAnimatingTargetObject) {
        [self assumeShiftDeltaAndApplyToTargetAccordingToOffset:offset andInset:inset];
    }
    else if (!_scrollView.isDragging && ![self isLimitForCurrentInterfaceOrientationReached] && !_isAnimatingTargetObject) {
        [self animateTargetToReachLimitForCurrentDirection];
    }
    /*
     Be sure to call the superclass's implementation *if it implements it*.
     NSObject does not implement the method.
     
    [super observeValueForKeyPath:keyPath
                         ofObject:object
                           change:change
                          context:context];
     */
}

- (void)unregisterForChangeNotification {
    [_scrollView removeObserver:self forKeyPath:DZScrollingInspector_CONTENT_OFFSET_KEYPATH];
    [_scrollView removeObserver:self forKeyPath:DZScrollingInspector_CONTENT_INSET_KEYPATH];
}

- (void)assumeScrollDirection:(CGFloat)newOffset andInset:(CGFloat)newInset {
    DZScrollDirection scrollDirection = DZScrollDirectionNone;
    if (_offset < newOffset) {
        scrollDirection = DZScrollDirectionUp;
    }
    else if (_offset > newOffset) {
        scrollDirection = DZScrollDirectionDown;
    }
    
    if (scrollDirection != DZScrollDirectionNone) {
        _lastScrollDirectionThatWasntNone = scrollDirection;
    }
    
    _scrollDirection = scrollDirection;
}

- (void)assumeShiftDeltaAndApplyToTargetAccordingToOffset:(CGFloat)newOffset andInset:(CGFloat)newInset
{
    
    //NSLog(@"target %@, offset %f, inset %f", _targetObject, newOffset, newInset);
    
    
    
    // calculate movement delta
    CGFloat delta = (newInset + newOffset) - (_inset + _offset);
    
    CGFloat existingValue = [self getTargetCurrentValueForKeypath];
    
    BOOL existingValuePassesLimitation = NO;
    BOOL scrollingBeyondBounds = NO; // means bouncing
    CGFloat directionCoefficient = 1.0f;
    
    DZScrollingInspectorLimit l = [self limitForCurrentInterfaceOrientation];
    
    if (l.min < l.max &&
        existingValue >= l.min && existingValue <= l.max) {
        existingValuePassesLimitation = YES;
        directionCoefficient = 1.0f;
    }
    else if (l.min > l.max &&
         existingValue <= l.min && existingValue >= l.max) {
        existingValuePassesLimitation = YES;
        directionCoefficient = -1.0f;
    }
    
    if (newOffset < -newInset) {
        scrollingBeyondBounds = YES;
    }
    
    
    if (existingValuePassesLimitation && !scrollingBeyondBounds) {
        CGFloat shiftedValue = existingValue + delta * directionCoefficient;
        shiftedValue = [DZScrollingInspector clampFloat:shiftedValue withMinimum:l.min andMaximum:l.max];
        
        //NSLog(@"existing %f, shifted %f", existingValue, shiftedValue);
        
        if (existingValue != shiftedValue) {
            [self setTargetValueForKeypathWithNewValue:shiftedValue];
        }
    }


    // set stored values
    _offset = newOffset;
    _inset = newInset;
}

- (void)animateTargetToReachLimitForCurrentDirection
{
    NSNumber *targetValueThatMatchesLimit = nil;
    switch (_lastScrollDirectionThatWasntNone) {
        case DZScrollDirectionDown:
            targetValueThatMatchesLimit = [NSNumber numberWithFloat:[self limitForCurrentInterfaceOrientation].max];
            break;
            
        case DZScrollDirectionUp:
            targetValueThatMatchesLimit = [NSNumber numberWithFloat:[self limitForCurrentInterfaceOrientation].min];
            break;
            
        case DZScrollDirectionNone:
            
            break;
            
        default:
            break;
    }
    
    NSLog(@"Animation should take place to value: %f", targetValueThatMatchesLimit.floatValue);
    
    if (targetValueThatMatchesLimit) {
        if ([_targetObject isKindOfClass:[UIView class]]) {
            [UIView animateWithDuration:0.1f delay:0.0f options:UIViewAnimationOptionAllowAnimatedContent animations:^{
                _isAnimatingTargetObject = true;
                [self setTargetValueForKeypathWithNewValue:targetValueThatMatchesLimit.floatValue];
            } completion:^(BOOL finished) {
                _isAnimatingTargetObject = false;
            }];
        }
    }
}

- (BOOL)isLimitForCurrentInterfaceOrientationReached
{
    CGFloat currentTargetValue = [self getTargetCurrentValueForKeypath];
    DZScrollingInspectorLimit currentLimit = [self limitForCurrentInterfaceOrientation];
    return currentTargetValue == currentLimit.min || currentTargetValue == currentLimit.max;
}

- (DZScrollingInspectorLimit)limitForCurrentInterfaceOrientation
{
    UIInterfaceOrientation currentInterfaceOrientation = [UIApplication sharedApplication].statusBarOrientation;
    return UIInterfaceOrientationIsPortrait(currentInterfaceOrientation) ? _limits.portraitLimit : _limits.landscapeLimit;
}

- (CGFloat)getTargetCurrentValueForKeypath
{
    return [DZScrollingInspector frameValueForKey:_targetFramePropertyKeyPath fromObject:_targetObject];
}

- (void)setTargetValueForKeypathWithNewValue:(CGFloat)newValue
{
    [DZScrollingInspector setFrameValue:newValue forKey:_targetFramePropertyKeyPath forObject:_targetObject];
}



-(void)suspend
{
    _isSuspended = YES;
}

-(void)resume
{
    _isSuspended = NO;
}

-(void)dealloc
{
    [self unregisterForChangeNotification];
}

#pragma mark - Static helpers
/*
 clamps the value to lie betweem minimum and maximum;
 if minimum is smaller than maximum - they will be swapped;
 */
+(CGFloat)clampFloat:(CGFloat)value withMinimum:(CGFloat)min andMaximum:(CGFloat)max {
    CGFloat realMin = min < max ? min : max;
    CGFloat realMax = max >= min ? max : min;
    return MAX(realMin, MIN(realMax, value));
}

DZScrollingInspectorTwoOrientationsLimits DZScrollingInspectorTwoOrientationsLimitsMake(CGFloat portraitMin, CGFloat portraitMax, CGFloat landscapeMin, CGFloat landscapeMax) {
    DZScrollingInspectorLimit portraitLimit;
    portraitLimit.min = portraitMin;
    portraitLimit.max = portraitMax;
    
    DZScrollingInspectorLimit landscapeLimit;
    landscapeLimit.max = landscapeMax;
    landscapeLimit.min = landscapeMin;
    
    DZScrollingInspectorTwoOrientationsLimits result;
    result.portraitLimit = portraitLimit;
    result.landscapeLimit = landscapeLimit;
    
    return result;
}


/*
 possible keys:
 x
 y
 */
+(CGFloat)contentOffsetValueForKey:(NSString*)key fromObject:(id)object
{
    if (!object) {
        [NSException raise:NSInvalidArgumentException format:@"Argument 'object' must be non-nil"];
    }
    if (!key) {
        [NSException raise:NSInvalidArgumentException format:@"Argument 'key' must be non-nil"];
    }
    
    NSValue *contentOffsetValue = [object valueForKeyPath:DZScrollingInspector_CONTENT_OFFSET_KEYPATH];
    CGFloat contentOffsetFloat = [DZScrollingInspector contentOffsetValueForKey:key fromCGPoint:contentOffsetValue.CGPointValue];
    return contentOffsetFloat;
}

+(CGFloat)contentOffsetValueForKey:(NSString*)key fromCGPoint:(CGPoint)contentOffsetPoint
{
    if (!key) {
        [NSException raise:NSInvalidArgumentException format:@"Argument 'key' must be non-nil"];
    }
    
    NSDictionary *contentOffsetDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                             [NSNumber numberWithFloat:contentOffsetPoint.y], @"y",
                                             [NSNumber numberWithFloat:contentOffsetPoint.x], @"x",
                                             nil];
    
    NSNumber *offsetNumber = [contentOffsetDictionary objectForKey:key];
    
    return offsetNumber.floatValue;
}

/*
 possible keys:
 top
 bottom
 left
 right
 */
+(CGFloat)contentInsetValueForKey:(NSString*)key fromObject:(id)object
{
    if (!object) {
        [NSException raise:NSInvalidArgumentException format:@"Argument 'object' must be non-nil"];
    }
    if (!key) {
        [NSException raise:NSInvalidArgumentException format:@"Argument 'key' must be non-nil"];
    }
    
    NSValue *contentInsetValue = [object valueForKeyPath:DZScrollingInspector_CONTENT_INSET_KEYPATH];
    UIEdgeInsets contentInsetEdgeInsets = contentInsetValue.UIEdgeInsetsValue;
    
    NSDictionary *contentInsetDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                             [NSNumber numberWithFloat:contentInsetEdgeInsets.top], @"top",
                                             [NSNumber numberWithFloat:contentInsetEdgeInsets.bottom], @"bottom",
                                             [NSNumber numberWithFloat:contentInsetEdgeInsets.left], @"left",
                                             [NSNumber numberWithFloat:contentInsetEdgeInsets.right], @"right",
                                             nil];
    
    NSNumber *insetNumber = [contentInsetDictionary objectForKey:key];
    
    return insetNumber.floatValue;
}

/*
 possible keys:
 origin.x
 origin.y
 size.width
 size.height
 */
+(CGFloat)frameValueForKey:(NSString*)key fromObject:(id)object
{
    if (!object) {
        [NSException raise:NSInvalidArgumentException format:@"Argument 'object' must be non-nil"];
    }
    if (!key) {
        [NSException raise:NSInvalidArgumentException format:@"Argument 'key' must be non-nil"];
    }
    
    NSValue *frameValue = [object valueForKeyPath:DZScrollingInspector_FRAME_KEYPATH];
    CGRect frameRect = frameValue.CGRectValue;
    
    NSDictionary *originDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSNumber numberWithFloat:frameRect.origin.x], @"x",
                                      [NSNumber numberWithFloat:frameRect.origin.y], @"y",
                                      nil];
    
    NSDictionary *sizeDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSNumber numberWithFloat:frameRect.size.width], @"width",
                                      [NSNumber numberWithFloat:frameRect.size.height], @"height",
                                      nil];
    
    NSDictionary *frameDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                     originDictionary, @"origin",
                                     sizeDictionary, @"size",
                                     nil];
    
    NSArray *keyComponents = [key componentsSeparatedByString:@"."];
    
    int keyComponentsCount = keyComponents.count;
    int i = 0;
    NSDictionary *nextLevelDictionary = frameDictionary;
    NSNumber *foundNumber = nil;
    
    while (i < keyComponentsCount) {
        nextLevelDictionary = [nextLevelDictionary objectForKey:[keyComponents objectAtIndex:i]];
        if ([nextLevelDictionary isKindOfClass:[NSNumber class]]) {
            foundNumber = (NSNumber*)nextLevelDictionary;
            
            break;
        }
        i++;
    }
    
    if (!foundNumber) {
        [NSException raise:NSInvalidArgumentException format:@"Cannot find frame value for key '%@'",key];
    }
    
    NSNumber *frameValueNumber = foundNumber;
    
    return frameValueNumber.floatValue;
    
}

+(void)setFrameValue:(CGFloat)floatValueToSet forKey:(NSString*)key forObject:(id)object
{
    if (!object) {
        [NSException raise:NSInvalidArgumentException format:@"Argument 'object' must be non-nil"];
    }
    if (!key) {
        [NSException raise:NSInvalidArgumentException format:@"Argument 'key' must be non-nil"];
    }
    
    NSArray *keyComponents = [key componentsSeparatedByString:@"."];
    
    BOOL successfullySet = NO;
    
    NSValue *frameValue = [object valueForKeyPath:DZScrollingInspector_FRAME_KEYPATH];
    CGRect frame = frameValue.CGRectValue;
    
    if (keyComponents.count > 1) {
        if ([[keyComponents objectAtIndex:0] isEqualToString:@"origin"]) {
            if ([[keyComponents objectAtIndex:1] isEqualToString:@"x"]) {
                frame.origin.x = floatValueToSet;
                successfullySet = YES;
            }
            if ([[keyComponents objectAtIndex:1] isEqualToString:@"y"]) {
                frame.origin.y = floatValueToSet;
                successfullySet = YES;
            }
        }
        else if ([[keyComponents objectAtIndex:0] isEqualToString:@"size"]) {
            if ([[keyComponents objectAtIndex:1] isEqualToString:@"width"]) {
                frame.size.width = floatValueToSet;
                successfullySet = YES;
            }
            if ([[keyComponents objectAtIndex:1] isEqualToString:@"height"]) {
                frame.size.height = floatValueToSet;
                successfullySet = YES;
            }
        }
    }
    
    [object setValue:[NSValue valueWithCGRect:frame] forKeyPath:DZScrollingInspector_FRAME_KEYPATH];
    
    if (!successfullySet) {
        [NSException raise:NSInvalidArgumentException format:@"Cannot find frame value for key '%@'",key];
    }
}
@end
