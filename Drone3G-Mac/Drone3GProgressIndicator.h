//
//  Drone3GProgressIndicator.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-10-18.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface Drone3GProgressIndicator : NSView {
    BOOL isAnimating;
    CGFloat frameIndex;
    
    NSTimer* animationTimer;
}

@property (nonatomic, readonly) BOOL isAnimating;

- (void)startAnimation;
- (void)stopAnimation;

@end
