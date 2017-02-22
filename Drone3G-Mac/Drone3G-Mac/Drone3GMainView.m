//
//  Drone3GMainView.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 1/20/2014.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GMainView.h"
#import "drone_main.h"
#import <sys/time.h>

@implementation Drone3GMainView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];
    
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
    
    if(drone3g_bmpctx == NULL) {
        CGContextSetRGBFillColor(context, 0, 0, 0, 1);
        CGContextFillRect(context, NSRectToCGRect(self.frame));
        
        return;
    }
    
    CGImageRef bitMapImage = CGBitmapContextCreateImage(drone3g_bmpctx);
    CGContextDrawImage(context, NSRectToCGRect(self.frame), bitMapImage);
    CGImageRelease(bitMapImage);
}

- (BOOL)isOpaque {
    return YES;
}

@end
