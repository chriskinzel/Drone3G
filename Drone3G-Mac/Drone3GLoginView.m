//
//  Drone3GLoginView.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-09-04.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "Drone3GLoginView.h"

@implementation Drone3GLoginView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        animating = NO;
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    
    // Drawing code here.
}

- (void)enableEditing {
    [NSTimer scheduledTimerWithTimeInterval:0.5f target:self selector:@selector(_enableEditing) userInfo:nil repeats:NO];
}

- (void)_enableEditing {
    for(int i=1;i<=3;i++) {
        [[self viewWithTag:i] setEditable:YES];
    }
}

- (void)disableEditing {
    for(int i=1;i<=3;i++) {
        [[self viewWithTag:i] setEditable:NO];
    }
}

- (void)adjustFontSize:(CGFloat)scale {
    for(int i=1;i<=3;i++) {
        [[self viewWithTag:i] setFont:[NSFont systemFontOfSize:13*scale]];
    }
    for(int i=4;i<=5;i++) {
        [[self viewWithTag:i] setFont:[NSFont systemFontOfSize:18*scale]];
    }
    
    [[self viewWithTag:6] setFont:[NSFont systemFontOfSize:17*scale]];
    [[self viewWithTag:7] setFont:[NSFont systemFontOfSize:11*scale]];
}

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag {
    animating = !flag;
}

- (void)shakeWindow {
    if(animating) {
        return;
    }
    
    static int numberOfShakes = 3;
    static float durationOfShake = 0.5f;
    static float vigourOfShake = 0.05f;
    
    CGRect frame=[self.window frame];
    CAKeyframeAnimation *shakeAnimation = [CAKeyframeAnimation animation];
    
    [shakeAnimation setDelegate:self];
    
    CGMutablePathRef shakePath = CGPathCreateMutable();
    CGPathMoveToPoint(shakePath, NULL, NSMinX(frame), NSMinY(frame));
    for (NSInteger index = 0; index < numberOfShakes; index++){
        CGPathAddLineToPoint(shakePath, NULL, NSMinX(frame) - frame.size.width * vigourOfShake, NSMinY(frame));
        CGPathAddLineToPoint(shakePath, NULL, NSMinX(frame) + frame.size.width * vigourOfShake, NSMinY(frame));
    }
    CGPathCloseSubpath(shakePath);
    shakeAnimation.path = shakePath;
    shakeAnimation.duration = durationOfShake;
    
    [self.window setAnimations:[NSDictionary dictionaryWithObject: shakeAnimation forKey:@"frameOrigin"]];
    
    frame = [[self.window parentWindow] frame];
    shakeAnimation = [CAKeyframeAnimation animation];
    
    [shakeAnimation setDelegate:self];
    
    shakePath = CGPathCreateMutable();
    CGPathMoveToPoint(shakePath, NULL, NSMinX(frame), NSMinY(frame));
    for (NSInteger index = 0; index < numberOfShakes; index++){
        CGPathAddLineToPoint(shakePath, NULL, NSMinX(frame) - frame.size.width * vigourOfShake, NSMinY(frame));
        CGPathAddLineToPoint(shakePath, NULL, NSMinX(frame) + frame.size.width * vigourOfShake, NSMinY(frame));
    }
    CGPathCloseSubpath(shakePath);
    shakeAnimation.path = shakePath;
    shakeAnimation.duration = durationOfShake;
    
    [[self.window parentWindow] setAnimations:[NSDictionary dictionaryWithObject: shakeAnimation forKey:@"frameOrigin"]];
    
    animating = YES;
    
    [[[self.window parentWindow] animator] setFrameOrigin:[self.window frame].origin];
    [[self.window animator] setFrameOrigin:[self.window frame].origin];

}

#pragma mark -
#pragma mark Getters
#pragma mark -

- (NSString*)getUsername {
    return [[self viewWithTag:1] stringValue];
}

- (NSString*)getPassword {
    return [[self viewWithTag:2] stringValue];
}

- (NSString*)getDroneName {
    return [[self viewWithTag:3] stringValue];
}

@end
