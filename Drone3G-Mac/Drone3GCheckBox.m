//
//  Drone3GCheckBox.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-12-26.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GCheckBox.h"

@implementation Drone3GCheckBox

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        initialFrameSize = self.frame.size;
        state = 0;
    }
    return self;
}

- (BOOL)isChecked {
    return (state == 1);
}

- (void)mouseDown:(NSEvent *)theEvent {
    // This code is for check box click only
    /*CGPoint clickPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    CGRect checkRect = CGRectMake(self.frame.size.width*0.015f, self.frame.size.height/3.0, self.frame.size.width*0.03f, self.frame.size.height*0.5);
    
    if(CGRectContainsPoint(checkRect, clickPoint)) {
        state = 1-state;
        
        [self setNeedsDisplay:YES];
    }*/
    
    // This code does full frame
    state = 1-state;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    // Calculate scale
    float scaleX = self.frame.size.width / initialFrameSize.width;
    float scaleY = self.frame.size.height / initialFrameSize.height;
    float scale = (scaleX < scaleY) ? scaleX : scaleY;
    
    // Scale font
    [[self viewWithTag:1] setFont:[NSFont systemFontOfSize:10.0*scale]];
    
    // Draw box
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSetStrokeColorWithColor(ctx, [[NSColor whiteColor] CGColor]);
    CGContextSetLineWidth(ctx, scale*1.5f);
    CGContextStrokeRect(ctx, CGRectMake(self.frame.size.width*0.015f, self.frame.size.height/3.0, self.frame.size.width*0.03f, self.frame.size.height*0.5));

    // Draw check
    if(state == 1) {
        CGContextSetLineWidth(ctx, scale*2.0f);
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, self.frame.size.width*0.015f + self.frame.size.width*0.01f, self.frame.size.height/3.0 + self.frame.size.height*0.4);
        CGContextAddLineToPoint(ctx, (self.frame.size.width*0.015f + self.frame.size.width*0.03f) * 0.7f, self.frame.size.height/3.0 * 1.5);
        CGContextMoveToPoint(ctx, (self.frame.size.width*0.015f + self.frame.size.width*0.03f) * 0.7f, self.frame.size.height/3.0 * 1.52);
        CGContextAddLineToPoint(ctx, (self.frame.size.width*0.015f + self.frame.size.width*0.03f) * 3.0f, (self.frame.size.height/3.0 + self.frame.size.height*0.5)*3.0);
        CGContextStrokePath(ctx);
        
        CGContextSetFillColorWithColor(ctx, [[NSColor whiteColor] CGColor]);
        CGContextFillRect(ctx, CGRectMake((self.frame.size.width*0.015f + self.frame.size.width*0.03f) * 0.65f, self.frame.size.height/3.0 * 1.45, self.frame.size.width*0.005f, self.frame.size.height*0.1f));
    }
}

@end
