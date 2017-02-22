//
//  Drone3GScrollView.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2015-01-05.
//  Copyright (c) 2015 Chris Kinzel. All rights reserved.
//

#import "Drone3GScrollViewOverlay.h"

@implementation Drone3GScrollViewOverlay

// Draws a rounded white box
- (void)drawRect:(NSRect)dirtyRect {
    NSRect rect = NSMakeRect([self bounds].origin.x + 3, [self bounds].origin.y + 3, [self bounds].size.width - 6, [self bounds].size.height - 6);
    
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:25.0 yRadius:25.0];
    [path addClip];
    
    /*[[NSColor colorWithCalibratedRed:0.2f green:0.2f blue:0.2f alpha:0.1f] set];
     NSRectFill(rect);*/
    
    [[NSColor whiteColor] set];
    
    [path setLineWidth:3.0];
    [path stroke];
    
    [super drawRect:dirtyRect];
}

@end
