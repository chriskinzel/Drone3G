//
//  Drone3GProgressIndicator.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-10-18.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GProgressIndicator.h"

#define FRAME_RATE 30
#define GROWTH_LIM 30.0f

@implementation Drone3GProgressIndicator

@synthesize isAnimating;

- (void)startAnimation {
    frameIndex = 0.0f;
    animationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f/FRAME_RATE target:self selector:@selector(nextImage) userInfo:nil repeats:YES];
    
    isAnimating = YES;
    
    [self setHidden:NO];
}

- (void)stopAnimation {
    [self setHidden:YES];
    
    [animationTimer invalidate];
    isAnimating = NO;
}

- (void)nextImage {
    [self setNeedsDisplay:YES];
    
    frameIndex += 2.0f*M_PI/FRAME_RATE;
    if(frameIndex >= 2*M_PI) {
        frameIndex = 0.0f;
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    CGFloat frameWidth = [self frame].size.width;
    CGFloat frameHeight = [self frame].size.height;
    
    NSGraphicsContext* gContext = [NSGraphicsContext currentContext];
    CGContextRef ctx = [gContext graphicsPort];
    
    CGContextSetFillColorWithColor(ctx, [[NSColor colorWithCalibratedRed:1 green:1 blue:1 alpha:0.85f] CGColor]);
    
    CGFloat r3_exp2 = exp2f(cosf(frameIndex));
    CGFloat r2_exp2 = exp2f(cosf(frameIndex + M_PI/3));
    CGFloat r1_exp2 = exp2f(cosf(frameIndex + 2*M_PI/3));
    
    CGFloat default_r = frameWidth/6;
    
    CGFloat r3 = default_r + frameWidth/GROWTH_LIM * sinf(frameIndex) * r3_exp2 * r3_exp2 / 1.5;
    CGFloat r2 = default_r + frameWidth/GROWTH_LIM * sinf(frameIndex + M_PI/3) * r2_exp2 * r2_exp2 / 1.5;
    CGFloat r1 = default_r + frameWidth/GROWTH_LIM * sinf(frameIndex + 2*M_PI/3) * r1_exp2 * r1_exp2 / 1.5;
    
    CGContextFillEllipseInRect(ctx, CGRectMake(4.0f/54.0f*frameWidth, frameHeight/2, r1, r1) );
    CGContextFillEllipseInRect(ctx, CGRectMake(frameWidth/2 - frameWidth/12, frameHeight/2, r2, r2) );
    CGContextFillEllipseInRect(ctx, CGRectMake(frameWidth-frameWidth/6 - 4.0f/54.0f*frameWidth, frameHeight/2, r3, r3) );
}

@end
