//
//  Drone3GHUD.h
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-08-07.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import <Cocoa/Cocoa.h>

// IMPORTANT: ANGLES ARE IN DEGREES

@interface Drone3GHUD : NSView {
    NSColor* inclinometerColor;
    
    float pitchAngle;
    float rollAngle;
    
    BOOL rendersInclinometer;
}

- (void)setRendersInclinometer:(BOOL)renders;

- (void)updateInclinometer:(float)pitch roll:(float)roll;
- (void)updateInclinometerColor:(NSColor*)hudColor;

@end
