//
//  Drone3GTextView.m
//  Drone3G-Mac
//
//  Created by Chris Kinzel on 2015-01-04.
//  Copyright (c) 2015 Chris Kinzel. All rights reserved.
//

#import "Drone3GTextView.h"

@implementation Drone3GTextView

// Need some padding on the top due to the rounded corners
- (void)awakeFromNib {
    [super setTextContainerInset:NSMakeSize(14.0f, 15.0f)];
}

- (NSView *)hitTest:(NSPoint)aPoint {
    // Pass-through events that don't hit one of the visible subviews
    for (NSView *subView in [self subviews]) {
        if (![subView isHidden] && [subView hitTest:aPoint])
            return subView;
    }
    
    return nil;
}

// Rounded corners
- (void)drawRect:(NSRect)dirtyRect {
    NSRect rect = NSMakeRect([self bounds].origin.x + 3, [self bounds].origin.y + 3, [self bounds].size.width - 6, [self bounds].size.height - 6);
    
    [[NSColor colorWithCalibratedRed:0.1f green:0.1f blue:0.1f alpha:0.3f] set];
    NSRectFill(rect);
    
    [super drawRect:dirtyRect];
}

@end
