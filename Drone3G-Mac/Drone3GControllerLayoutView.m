//
//  Drone3GControllerLayoutView.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2014-03-23.
//  Copyright (c) 2014 Chris Kinzel. All rights reserved.
//

#import "Drone3GControllerLayoutView.h"

@implementation Drone3GControllerLayoutView

/*- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    return self;
}*/

static CGPoint draw_line(CGContextRef context, CGPoint startPoint, float angle, float length) {
    angle = angle/180.0f * 3.141592653589793f; // Convert angle to radians
    
    CGPoint endPoint = CGPointMake(startPoint.x + cosf(angle)*length, startPoint.y + sinf(angle)*length);
    
    CGContextMoveToPoint(context, startPoint.x, startPoint.y);
    CGContextAddLineToPoint(context, endPoint.x, endPoint.y);
    CGContextStrokePath(context);
    
    return endPoint;
}

- (void)drawRect:(NSRect)dirtyRect {
	[super drawRect:dirtyRect];
    
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
    NSColor* drawingColor = [NSColor controlShadowColor];
    
    CGContextSetStrokeColorWithColor(context, [drawingColor CGColor]);
    CGContextSetLineWidth(context, 2.0f);
    
    float offsetY = self.frame.size.height - 397; // Original numbers where for view height 397
    float baseX = 88.0f; // When I changed the width one time everything got messed up so I fixed it with this
    
    // R1
    CGPoint endPoint = draw_line(context, CGPointMake(450+baseX, 299+offsetY), 45.0f, 39.0f);
    draw_line(context, endPoint, 0, 103);
    
    // L1
    endPoint = draw_line(context, CGPointMake(163+baseX, 299+offsetY), 45.0f+90.0f, 37.0f);
    draw_line(context, endPoint, 180, 94);
    
    // R2
    endPoint = draw_line(context, CGPointMake(430+baseX, 298+offsetY), 70.0f, 69.0f);
    draw_line(context, endPoint, 0, 125);
    
    // L2
    endPoint = draw_line(context, CGPointMake(178+baseX, 298+offsetY), 110.0f, 67.0f);
    draw_line(context, endPoint, 180, 112);
    
    
    // Left Stick
    endPoint = draw_line(context, CGPointMake(229+baseX, 120+offsetY), 270.0f-20.0f, 123.0f);
    draw_line(context, endPoint, 180, 105);
    
    // Left Stick Button
    endPoint = draw_line(context, CGPointMake(229+baseX, 120+offsetY), 270.0f-10, 149.0f);
    draw_line(context, endPoint, 180, 115);
    
    // Right Stick
    endPoint = draw_line(context, CGPointMake(383+baseX, 120+offsetY), 270.0f+20.0f, 120.0f);
    draw_line(context, endPoint, 0, 105);
    
    // Right Stick Button
    endPoint = draw_line(context, CGPointMake(383+baseX, 120+offsetY), 270.0f+10, 146.0f);
    draw_line(context, endPoint, 0, 125);
    
    // Square
    endPoint = draw_line(context, CGPointMake(410+baseX, 195+offsetY), 270.0f+28.0f, 46.0f);
    draw_line(context, endPoint, 0, 142);
    
    // Right arrow
    endPoint = draw_line(context, CGPointMake(188+baseX, 196+offsetY), 270.0f-20.0f, 45.0f);
    draw_line(context, endPoint, 180, 138);
}

@end
