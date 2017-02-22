//
//  Drone3GHUD.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-08-07.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GHUD.h"
#import "Drone3GAppDelegate.h"

#define INCLINOMETER_W_SCALE 0.7
#define INCLINOMETER_HAT_H_SCALE 1.0

@implementation Drone3GHUD

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        inclinometerColor = [NSColor greenColor];
        
        pitchAngle = 0.0f;
        rollAngle = 0.0f;
    }
    return self;
}

- (void)updateInclinometer:(float)pitch roll:(float)roll {
    pitchAngle = pitch;
    rollAngle = roll;
    
    [self setNeedsDisplay:YES];
}

- (void)updateInclinometerColor:(NSColor*)hudColor {
    inclinometerColor = hudColor;
    [self setNeedsDisplay:YES];
}

- (void)setRendersInclinometer:(BOOL)renders {
    rendersInclinometer = renders;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    
    if(rendersInclinometer && [[(Drone3GAppDelegate*)[[NSApplication sharedApplication] delegate] connectionLabel] isHidden]) {
        NSBezierPath* inclinometer = [NSBezierPath bezierPath];
        [inclinometer moveToPoint:NSMakePoint(NSMinX([self bounds]) + (1-INCLINOMETER_W_SCALE)*NSMaxX([self bounds]), NSMaxY([self bounds])/2)];
        [inclinometer lineToPoint:NSMakePoint(NSMaxX([self bounds])/2*0.95, NSMaxY([self bounds])/2)];
        [inclinometer lineToPoint:NSMakePoint(NSMaxX([self bounds])/2, NSMaxY([self bounds])/2/1.05*INCLINOMETER_HAT_H_SCALE)];
        [inclinometer lineToPoint:NSMakePoint(NSMaxX([self bounds])/2*1.05, NSMaxY([self bounds])/2)];
        [inclinometer lineToPoint:NSMakePoint(NSMaxX([self bounds])*INCLINOMETER_W_SCALE, NSMaxY([self bounds])/2)];
        
        NSAffineTransform* rotation = [NSAffineTransform transform];
        [rotation translateXBy:self.bounds.size.width/2 yBy:self.bounds.size.height/2];
        [rotation rotateByDegrees:-rollAngle];
        [rotation translateXBy:-self.bounds.size.width/2 yBy:-self.bounds.size.height/2];
        
        NSAffineTransform* translation = [NSAffineTransform transform];
        [translation translateXBy:0 yBy:sinf(-pitchAngle*M_PI/180.0f)*self.bounds.size.height/2];
        
        NSAffineTransform* transform = [NSAffineTransform transform];
        [transform appendTransform:rotation];
        [transform appendTransform:translation];
        
        NSBezierPath* translatedPath = [transform transformBezierPath:inclinometer];
        
        [translatedPath setLineWidth:1.0];
        [inclinometerColor set];
        
        [translatedPath stroke];
    }
}

@end
